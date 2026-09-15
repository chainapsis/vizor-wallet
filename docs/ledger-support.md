# Ledger support

This document is Vizor's Ledger support contract. It covers what works on which
platform and device, how accounts and signatures are checked, the limits a user
can hit, and what is still unverified. It describes the account-level cleanup on `rowan/ledger-advanced`
(2026-09-16, based on `7ef833bc0`). Ledger support is not on `main` and has not shipped.

"Implemented" means the code path exists. It does not mean every OS and Ledger
model was tested on a physical device; [Verification status](#verification-status)
records what was. This document replaces `docs/ledger-multi-account-import.md`
and the earlier Korean support review.

## At a glance

Ledger accounts work on Zcash mainnet for syncing, receiving, sending,
shielding, swap and pay deposits, and coinholder voting. macOS, Windows, and
Linux connect over USB or Bluetooth. iOS and Android connect over Bluetooth
only. Sapling, Orchard-to-Ironwood migration, receive-address verification on
the device, and mobile USB are not supported.

| Feature | macOS / Windows / Linux | iOS / Android | Conditions |
| --- | --- | --- | --- |
| Add as the first account | Implemented | Implemented | Approve the UFVK on the Ledger, then set the birthday and password or passcode |
| Add another account from the same Ledger | Implemented | Implemented | Each account index needs its own UFVK approval |
| Sync, balances, receive addresses | Implemented | Implemented | Uses the imported UFVK; no Ledger connection needed |
| Send | Implemented | Implemented | Pool, address, and capacity limits below |
| Send to a TEX address | Implemented | Implemented | Two dependent PCZTs, approved one after the other |
| Shield transparent funds | Implemented | Implemented | Up to 32 inputs per approval; larger balances continue in further rounds |
| Swap / Pay deposit | Implemented | Implemented | Signs the ZEC deposit only; the other chain's transaction is not signed on the Ledger |
| Coinholder voting | Implemented | Implemented | One approval per bundle; the device does not clear-sign the vote content |
| Orchard-to-Ironwood migration | Blocked | Blocked | Signer code remains; the product entry point is closed |
| Verify a receive address on the Ledger | Not implemented | Not implemented | Vizor shows and copies addresses; the device does not display them |
| Wallet Link, desktop to mobile | Exports Ledger accounts | Imports without the device | The first mobile signature enrolls a Bluetooth Ledger after matching the account UFVK |

Signing entry points: [send review](../lib/src/features/send/screens/send_review_screen.dart),
[mobile send](../lib/src/features/send/screens/mobile/mobile_ledger_send_sign_screen.dart),
[shield](../lib/src/features/home/widgets/ledger_shield_signing_overlay.dart),
[swap and pay](../lib/src/features/swap/widgets/swap_ledger_signing_overlay.dart), and the
[voting job](../lib/src/providers/voting/voting_submission_job_provider.dart). Every
screen goes through the same protocol and account checks before signing.

## Platforms and devices

### Connection by OS

| OS | Minimum OS in the build | USB | Bluetooth | Notes |
| --- | --- | --- | --- | --- |
| macOS | 12.0 | Rust HID | Apple `BleTransport` 1.0.1 | USB, Bluetooth, or Automatic; the Bluetooth handler shares the iOS source |
| Windows | 10/11 declared in the manifest; Bluetooth floor not verified | Rust HID | Vizor's C++/WinRT GATT adapter | USB, Bluetooth, or Automatic; needs a Bluetooth adapter |
| Linux | Not verified | Rust HID over `hidraw` | Vizor's C++ BlueZ adapter over GIO D-Bus | USB, Bluetooth, or Automatic; USB needs the udev rule, Bluetooth needs BlueZ and an LE adapter |
| iOS | 15.0 | Not supported | Apple `BleTransport` 1.0.1 | CoreBluetooth permission and state checks; reconnects after the Ledger switches apps |
| Android | 11 (API 30) | Not supported | Ledger Mobile DMK 0.0.4 | Scan and Connect permissions on 12+, location on 11; waits for GATT teardown |

Minimum OS values come from build settings, not from tests on the oldest
version. The iOS widget extension's 26.0 target is not the app's minimum.
Android `minSdk = 30` applies to the whole app, not only to Ledger, because DMK
0.0.4 requires it. DMK offers USB APIs, but Vizor Android does not implement
USB. The Windows results below come from a Windows 11 ARM64 VM running the x64
Release with a USB Bluetooth dongle; they do not certify Windows 10 or built-in
adapters.

Sources: [capability](../lib/src/features/ledger/ledger_capability.dart),
[Android Gradle](../android/app/build.gradle.kts),
[Android manifest](../android/app/src/main/AndroidManifest.xml),
[iOS project](../ios/Runner.xcodeproj/project.pbxproj),
[macOS project](../macos/Runner.xcodeproj/project.pbxproj),
[Windows manifest](../windows/runner/runner.exe.manifest), and
[Windows Bluetooth handler](../windows/runner/ledger_ble_handler.cpp). The macOS
sandbox has [USB and Bluetooth entitlements](../macos/Runner/Release.entitlements),
and iOS and macOS declare Bluetooth usage strings.

### Ledger models

| Model | Desktop USB | macOS / iOS Bluetooth | Android / Windows / Linux Bluetooth |
| --- | --- | --- | --- |
| Nano S Plus | HID | No Bluetooth hardware | No Bluetooth hardware |
| Nano X | HID | Allowed | Allowed |
| Stax, Flex | HID | Allowed | Allowed |
| Nano Gen5 / Apex | HID; not tested on a device | Blocked by the current transport | Allowed; not tested on a device |
| Nano S (original) | Not a support target | Not supported | Not supported |

"Allowed" means the [model capability](../lib/src/features/ledger/ledger_capability.dart)
permits it. Windows Bluetooth implements the service UUIDs for Nano X, Stax,
Flex, and Nano Gen5. Stax is the only model tested over Bluetooth. The upstream
app's [build targets](https://github.com/LedgerHQ/app-zcash/blob/22dc38537f9a84b31b938e3ca95434595ef378d3/ledger_app.toml)
are Nano X, Nano S Plus, Stax, Flex, and Apex, without the original Nano S.

USB finds devices by Ledger vendor ID and usage page rather than a model list.
With several Ledgers plugged in, Vizor uses the
[first match](../rust/src/wallet/ledger/transport.rs). There is no device picker,
so connect one Ledger at a time. A USB-imported account records the HID product
string as its device model, so the Bluetooth capability check works for it too.

### Linux USB permissions

`hidraw` access is separate from launching the app. The repository's
[udev rule](../linux/udev/20-vizor-ledger.rules) grants the logged-in local user
access to vendor `2c97` HID devices through the `uaccess` ACL. It follows the
vendor match in [Ledger's official rules](https://github.com/LedgerHQ/udev-rules/blob/master/20-hw1.rules).
The app never runs as root and never opens the device to every user.

Install it from the repository root, then reconnect the Ledger:

```sh
sudo install -m 644 linux/udev/20-vizor-ledger.rules /etc/udev/rules.d/20-vizor-ledger.rules
sudo udevadm control --reload-rules
```

Builds and bundles do not install the rule. On Linux, the USB permission error
points to Ledger's udev rules. Headless or SSH sessions without a graphical
login are out of scope.

### Bluetooth pairing

**Linux.** Vizor pairs through its own BlueZ agent instead of the desktop's
Bluetooth settings:

1. Right before each pairing, Vizor registers an `org.bluez.Agent1` as `DisplayYesNo`.
2. When BlueZ asks for confirmation, Vizor holds the reply and shows the
   six-digit code in the connect dialog or the signing modal, with
   "Pair only if your Ledger shows the same code."
3. The user compares the codes and taps **Codes match** or **Codes differ**.
   Only a match answers yes. The user then approves on the Ledger.

The agent answers only for the Ledger being connected, authorizes only the
Ledger GATT service, and rejects PIN, passkey, and Just Works requests. Without
a BlueZ agent manager, the session's own Bluetooth agent handles pairing. The
confirmation must come within the pairing window, about 30 seconds in testing
with Stax. A later confirmation fails on the Ledger with "Bluetooth pairing
failed" and needs a retry. Vizor never deletes existing bonds.

The device list shows only Ledgers the current discovery has seen (BlueZ
`RSSI`) or that are connected. A remembered bond that is powered off is hidden,
but reconnecting a saved device does not need the list. BlueZ Connect and Pair
failures map to `disconnected` and lead to reconnect guidance. A VM needs a
Bluetooth adapter passed through separately from the USB Ledger.

**Windows** pairs with encryption and authentication and may ask for Bluetooth
permission and pairing confirmation. **macOS, iOS, and Android** pair through the
OS and the Ledger transport SDK.

**Bluetooth for a USB-imported account.** Open the account menu (`⋯`), then
**Ledger connection** and **Set up Bluetooth**, and pick the device once. Vizor
stores the Bluetooth details only when the device's UFVK matches the existing
account. OS pairing alone does not enroll a device, and this flow never adds an
account.

Sources: [Linux transport](../linux/runner/ledger_bluez_transport.cc),
[Linux handler](../linux/runner/ledger_ble_handler.cc),
[pairing code provider](../lib/src/features/ledger/services/ledger_pairing_code_provider.dart).
Windows and Linux share the Ledger UUIDs, framing, MTU handling, and response
parser in [`native/ledger/ble_protocol.h`](../native/ledger/ble_protocol.h).

## Accounts and derivation metadata

### What Vizor holds

Vizor never receives the Ledger's seed or spending keys. It syncs, shows
balances, and derives receive addresses from the UFVK the user approved, and it
asks the device for every spend signature. A UFVK cannot spend, but it reveals
transaction history, so it is sensitive. The app password or passcode protects
the local wallet and is separate from the Ledger PIN. Ledger accounts have no
mnemonic entry, and the account menu does not offer to show a secret phrase.

### Identifiers

| Identifier | What it is | Do not treat it as |
| --- | --- | --- |
| `accountUuid` | The account's ID in the Vizor database | A Ledger device ID |
| ZIP-32 account index | Selects `m/32'/133'/index'`, and `m/44'/133'/index'` for transparent funds; `0..2147483647` | The display order |
| `seedFingerprint` | SHA-256 over `vizor-ledger-account-fingerprint-v1\0`, the index, and the UFVK; fills the 32-byte seed fingerprint slot in the database and in PCZTs | The real ZIP-32 seed fingerprint, which requires the seed |
| Bluetooth device ID, name, model | Rediscovery and display | Proof that the device holds the account |

The Zcash app does not export a seed fingerprint, so Vizor uses the account-scoped
substitute described above for DB and PCZT derivation metadata. The device does not check the PCZT seed fingerprint field:
app-zcash 3.9.3 only logs it while parsing (`src/parser/pczt/orchard.rs`,
`ironwood.rs`, `transparent.rs`) and checks keys by re-deriving them from the
path. Vizor compares the field with the selected account before signing.

### Adding accounts

Each ZIP-32 index is its own Vizor account and needs its own UFVK approval on
Ledger. Accounts are displayed independently, even when they share a seed.
Vizor does not group accounts, name Ledger wallets, or read a separate wallet
fingerprint. It does not scan account indexes for balances or history.

Use **Add account → Ledger**. The **Advanced · Account N** disclosure defaults
to index 0 and accepts `0..2147483647`. It shows the account-level paths
`m/32'/133'/N'` and `m/44'/133'/N'`. Receive-address rotation remains managed by
the wallet; there is no address-index input in account import.

After UFVK approval, Vizor compares the exported UFVK with existing accounts
before proceeding to the birthday step. The same account index on another
Ledger seed is allowed. Rust's UFVK import is the final duplicate guard.
A duplicate reports `This Ledger account is already in Vizor.`

The birthday, password or passcode, and account-name steps remain unchanged.
A rejection or disconnect keeps the chosen index for retry. Busy inputs are
disabled. Adding accounts no longer uses an existing account as a source or
suggests the next index for a Ledger wallet.

Sources: [account service](../lib/src/features/ledger/services/ledger_account_service.dart),
[account provider](../lib/src/providers/account_provider.dart),
[desktop connect screen](../lib/src/features/onboarding/ledger/ledger_connect_screen.dart), and
[mobile connect screen](../lib/src/features/onboarding/mobile/mobile_ledger_connect_screen.dart).

### Wallet Link

The encrypted transfer carries the UFVK, seed fingerprint, birthday, account
index, account name, and device model. Desktop Bluetooth IDs and transport
settings are not copied.

Importing and syncing need no Ledger. On the first signature, the reconnect
screen lets the user pick a Bluetooth Ledger. Vizor enrolls it only when
the exported UFVK matches the stored UFVK for that account. Connecting does not sign or
broadcast; the user taps **Try again** on the original signing screen. A
different Ledger is refused, and cancelling the connection signs nothing.

The server stores and returns the same ciphertext envelope, so it needed no
change, but both the exporting and importing clients need this version. Mobile
has no USB, so an account used only over USB needs a Bluetooth Ledger with the
same seed to sign on the phone. The device model travels so the Bluetooth
capability check works for accounts first imported over USB.

Sources: [export](../lib/src/features/wallet_link/providers/wallet_link_provider.dart),
[transfer model](../lib/src/features/wallet_link/models/wallet_link_models.dart), and
[signing modal](../lib/src/features/ledger/widgets/ledger_signing_modal.dart).

### Restoring and imported-only wallets

Adding a Ledger as the first account can leave the database with only imported
accounts. Recovering from a future seed-requiring migration is a separate
product task, and typing the Ledger seed into Vizor is not a recovery path. On a
new install, restore by approving the UFVK again from a Ledger with the same
seed; the user needs the index and birthday. Replacing the device for an
existing account is different from adding an account.

## Transactions

### Pools and formats

| Case | Handling |
| --- | --- |
| V5 Orchard / V6 Ironwood | PCZT serializer and signer |
| Transparent input | P2PKH, `SIGHASH_ALL`, one derivation under `m/44'/133'/account'/scope/index` (scope 0 or 1, or 2 for a TEX ephemeral input); the full signer collects the signatures |
| Transparent output | P2PKH and P2SH as upstream supports; no arbitrary scripts or multisig |
| TEX | Through an ephemeral transparent address; two PCZTs approved in order |
| Sapling input or output | Rejected by proposal validation and the PCZT parser, independent of Vizor's general Sapling support |
| Real Orchard spend with a valued Ironwood output | Rejected by the release-support guard, for sends and automatic migration |
| Dummy or zero-value action | Counts toward the wire action total; excluded from signature requests |

Sources: [parser](../rust/src/wallet/ledger/parse.rs),
[account and signature checks](../rust/src/wallet/ledger/mod.rs),
[selection and proposal limits](../rust/src/wallet/sync/send/ledger_selection.rs), and the
[official PCZT APDU contract](https://github.com/LedgerHQ/app-zcash/blob/22dc38537f9a84b31b938e3ca95434595ef378d3/docs/PCZT_APDU.md).

### Capacity per transaction

| Limit | Value | Effect on the user |
| --- | --- | --- |
| Transparent inputs | 32 per PCZT | Accounts with many UTXOs shield in rounds |
| Transparent outputs | 10 per PCZT | More outputs are rejected |
| Orchard actions | 32 per PCZT | Not always equal to the input count; includes padding and change |
| Ironwood actions | 32 per PCZT | Counted per pool, not combined with Orchard |
| Shielded outputs shown on the device | 4 across both pools | Upstream's review budget, excluding dummy and change outputs; Vizor has no host-side pre-check |
| APDU data | 255 bytes per packet | Large fields span several APDUs; a derivation stays in one packet |
| UFVK response | 8 KiB in the decoder and native Bluetooth code | Bad lengths, truncation, and trailing bytes are rejected |

There is no fixed maximum amount; the number of notes or UTXOs and the
transaction shape set the limit. The Ledger selector picks eligible notes
largest first so quotes, Max, and proposals fit. After NU6.3, legacy Orchard
selection keeps one action for change and picks at most 31 inputs. TEX applies
the limits to each PCZT separately. Max can be lower than the full balance:
on Ledger accounts, the desktop **Use Max** tooltip and a mobile help sheet say
"Max is also limited to what the device can sign in one transaction." Vizor
does not split a large send into several transfers.

Ledger Live 4.20.0 (2026-09-11) enforces the same 32 transparent-input and
32 Ironwood-note ceilings in its own selection
([ledger-live#21502](https://github.com/LedgerHQ/ledger-live/pull/21502)).

Sources: [serializer](../rust/src/wallet/ledger/serializer.rs),
[Ledger selector](../rust/src/wallet/sync/send/ledger_selection.rs),
[upstream limit constants](https://github.com/LedgerHQ/app-zcash/blob/22dc38537f9a84b31b938e3ca95434595ef378d3/src/consts.rs), and
[Max copy](../lib/src/core/widgets/spendable_balance_copy.dart).

### Shielding in rounds

One approval shields at most 32 transparent inputs, chosen in the selector's own
order so the quote matches the signed transaction. When an account holds more,
the home card says so: "Ledger shields up to 32 transparent inputs per approval.
Shielding all N inputs takes M approvals in a row on your Ledger." The shield
overlay then runs rounds:

1. Sign and broadcast up to 32 inputs.
2. Read the remaining input count and start the next round with a fresh
   approval. The signing modal shows the round as a badge, for example "2 of 3".
3. Finish only when no inputs remain.

If the remaining count cannot be read, or a round leaves it unchanged because
the broadcast has not freed its inputs yet, the overlay shows **Shielding
paused** with the reason and a way back to the wallet. It never asks the device
to sign the same inputs again.

Sources: [shield overlay](../lib/src/features/home/widgets/ledger_shield_signing_overlay.dart),
[home notice](../lib/src/features/home/providers/ledger_shielding_limit_notice_provider.dart), and
[messages](../lib/src/features/ledger/ledger_error_messages.dart).

### Signing flow and checks

```text
Vizor: validate proposal, account, and support range -> base PCZT
  |- Vizor: build proofs -> keep the proof PCZT
  `- Ledger: APDU review and approval -> spend signatures
Vizor: validate responses, account, and signatures -> checkpoint signed operation -> broadcast -> recover or clean up
```

Native Bluetooth code only connects and moves bytes. Rust builds and parses
every Zcash APDU. There is no wallet-fingerprint request before signing.
A different Ledger may be rejected only after approval when its signatures
fail validation. The signature checks and signing-status cooldown remain.
Vizor matches the PCZT's account paths and fingerprints against the database
account, and checks the response count, status, signature length, and signature
validity. `0x9000` alone never completes a send.

Sends, shielding, and swap or pay use the full signer. Voting uses the compact
signer, which returns the pool, action index, and 64-byte signature, and must
match exactly the one Ironwood action it expects. The voting UI's `displayMemo`
is shown by the host; the device is not guaranteed to display and approve the
proposal and choice in full.

Sources: [shared signer](../lib/src/features/ledger/services/ledger_signing_service.dart),
[Rust finalizer](../rust/src/wallet/ledger/mod.rs), and
[voting signature intake](../lib/src/providers/voting/voting_session_provider.dart).

## Connection, cancellation, and retries

An invalid Bluetooth pairing shows **Pair your Ledger again** and asks the user
to forget the Ledger in their device's Bluetooth settings, then reconnect.
**Try again** restarts discovery or connection recovery; it does not sign.
**Open Bluetooth settings** is available on macOS, Windows, and Android. iOS
and Linux retain the manual instruction because there is no shared supported
shortcut here. The Apple adapter recognizes CoreBluetooth's removed-pairing
error, including its localized description preserved by BleTransport. Generic
pairing rejection and ordinary disconnection do not imply invalid pairing.


| Situation | Handling | Limit |
| --- | --- | --- |
| Dashboard or another app open | Ask to open Zcash, then re-read the running app and version | Locked, rejected, or outdated states are not hidden behind automatic retries |
| Automatic transport on desktop | Try the last successful transport first, then the other one | Falls back only when connecting fails **before** the operation starts |
| Error after the operation starts | Return the error; the user chooses reconnect or retry | The same signature is never replayed on another transport |
| Bluetooth reconnect | Cancel, disconnect, rediscover for up to 15 s, connect, check readiness | Being ready again does not re-sign or re-send |
| `0x6901` (device busy starting a review) | Retry only the refused APDU, up to 3 attempts 200 ms apart | APDUs that already succeeded are not resent |
| Next command right after a signature request | Wait until 4 s after that request ended | See [Status screen after signing](#status-screen-after-signing) |
| User cancels | Cancel the shared native UFVK or PCZT request, ignore late results, stop Dart retries | Does not interrupt a physical exchange; a prompt already on the device may need to be finished or rejected there |
| Leaving a screen with a pending request | The screen cancels its device request when it is disposed, like Cancel; mobile voting back and the system back gesture cancel before leaving | The prompt on the device follows the row above |
| After device approval | Swap and pay block leaving during checkpoint and broadcast; a failed broadcast shows as queued | An approved deposit cannot be cancelled; recovery resends only before the deadline |

### Status screen after signing

After it returns the last signature of a transaction, the Zcash app shows a
status screen for 3 seconds. It does the same after the user rejects a review
and after commands that display an address or UFVK. While that screen is up,
the device SDK (`ledger_device_sdk` 1.37.0, legacy I/O) takes an incoming app
command and never answers it, so the host waits until its own deadline.
Get-app-and-version (`CLA 0xB0`) is answered by the OS layer and is unaffected.
Ledger's reviewers measured the same window on Speculos: two requests 400 ms
apart hang and 5 s apart pass
([ledger-live#21520](https://github.com/LedgerHQ/ledger-live/pull/21520)).

Vizor records when each signature request ends, whether it succeeded or failed,
and sends no device command until 4 seconds after that. On desktop USB, every
device operation waits in the Rust operation lock. On Bluetooth, the
signing exchange runs inside the signing gate, while
get-app-and-version may run earlier. The extra second covers the device timer's
slack. A UFVK approval also shows
the screen, but the import and Bluetooth enrollment flows send no device
command right after it.

Sources: [Rust operation lock](../rust/src/wallet/ledger/mod.rs),
[Bluetooth signing gate](../lib/src/features/ledger/services/ledger_signing_service.dart), and
[app-zcash status screen](https://github.com/LedgerHQ/app-zcash/blob/22dc38537f9a84b31b938e3ca95434595ef378d3/src/main.rs).

### Transport details

**Desktop USB** uses one Rust transport on all three OSes, with an operation
mutex, a 5-minute operation deadline, and 100 ms HID polling. USB errors tell
apart a missing device, denied permission (the udev rule on Linux), a device
held by another app, and an interrupted link.

**Apple** sends the open-app command once and then spends a 10-second budget
observing and reconnecting. Time the user spends approving the open on the
device does not count, and an SDK call that never returns is not forced to end,
so 10 seconds is not a wall-clock cap. `BleTransport` 1.0.1 cannot abort an
in-flight exchange. Cancelling completes the Dart result once, keeps the native
task slot until the SDK callback, and sends no continuation APDU after a late
first response. Reopening the device picker in that state asks the user to
finish or reject the previous request on the Ledger instead of waiting forever
for a disconnect. Scheduled `0x6901` retries do not run after cancel or
disconnect.

**Android** serializes connect and disconnect, then spends up to 5 seconds
confirming that the peer left both the GATT and DMK session lists. Until
cleanup finishes, further APDUs are blocked. The DMK's nullable device-name
exception is caught and returned as a typed error; the SDK itself is unchanged.

**Windows** runs one native request at a time with generation checks, and
cleans up the GATT session and notifications on cancel or disconnect. The MTU
honors both the payload size the Ledger announces and Windows' ATT limit.
Errors distinguish a missing adapter, Bluetooth turned off, and a rejected
pairing.

**Linux** carries the same framing over BlueZ notifications. An explicit
disconnect completes only after the cancelled worker and the physical
disconnect finish. If cleanup fails, the device path is kept so the next
connection cleans it up. The handler has no global timer; the transport allows
300 s per APDU exchange, 10 s for MTU setup, and 120 s for the Pair call.

Before a Bluetooth reconnect, Vizor asks for the Bluetooth permission again, so
a revoked permission shows as a permission error rather than a failed discovery.
Signing is not kept alive in the background, and resuming after an OS suspend is
not guaranteed.

Sources: [connection service](../lib/src/features/ledger/services/ledger_connection_service.dart),
[recovery controller](../lib/src/features/ledger/services/ledger_connection_recovery.dart),
[Bluetooth APDU retry](../lib/src/features/ledger/services/ledger_mobile_ble_service.dart),
[Apple handler](../ios/Runner/LedgerMobileHandler.swift),
[Android handler](../android/app/src/main/kotlin/com/keplr/vizor/LedgerMobileHandler.kt),
[Windows handler](../windows/runner/ledger_ble_handler.cpp),
[shared Bluetooth framing](../native/ledger/ble_protocol.h), and
[USB transport](../rust/src/wallet/ledger/transport.rs).

### What the user does for each error

| Error | What the user should do |
| --- | --- |
| Bluetooth off, permission denied, pairing failed | Fix Bluetooth, the permission, or pairing, then reconnect |
| USB: no device, permission denied, device in use, link interrupted | Connect and unlock the Ledger; on Linux install the udev rule; close other wallet apps using the Ledger; reconnect |
| Locked or rejected | Unlock the Ledger or review the request again; approvals are never retried automatically |
| Outdated or unreadable app version | Update the Zcash app or check the installed version |
| Signature mismatch from a different Ledger | Connect the Ledger that holds this account |
| `VIZOR_LEDGER_CAPACITY` | Send less; for swap, get a new quote; for pay, arrange a new amount with the merchant |
| `0x6986` | Check the selected account and build a new request; it is not a "send less" problem |
| Signature apply failure (`Apply Ledger … signature`) | Another Ledger signed; reconnect the Ledger this account was added from |
| More than 32 transparent inputs to shield | Continue through the rounds the home card describes |
| Legacy Orchard-to-Ironwood release guard | Shown as an app-update notice while composing; changing the amount does not help |
| `0x6f01` / `0x6f03` | Close and reopen the Zcash app to read the version or prepare the request again |
| Orchard-to-Ironwood unsupported | Stays blocked until a compatible app is verified; repeating the request does not help |

Pay amounts are never reduced by the user. The
[error mapping](../lib/src/features/ledger/ledger_error_messages.dart) keeps
separate copy for send, swap, pay, shield, migration, and voting.

## Recovery after signing

Send, shield, swap, and pay checkpoint the proof and signature PCZTs as a signed
operation in the Rust database before broadcasting. This is recovery data for a
request the device already approved; it does not mark the transaction complete
in wallet history before broadcast. A process that dies between signing and the
checkpoint is not covered.

| Saved state or result | Recovery contract |
| --- | --- |
| `signed_pending_broadcast` | After unlock and wallet readiness, resend with the saved signatures; no new Ledger approval |
| `result_pending_ack` | Hand the broadcast result to the wallet or to swap/pay activity, then acknowledge |
| Send or shield `broadcasted` | Normal completion; clean up |
| Swap or pay result | Record it against the external intent, then acknowledge |
| Unknown, partial, or unsaved result | Never assume success or restart as a new send; reconcile with the existing txid and wallet sync |
| Expired, or broadcast explicitly rejected | Stop retrying that signed operation; a new request is needed |
| Swap or pay `signed_pending_broadcast` past the deposit deadline or without its intent | Discard without broadcasting; Activity shows it expired by the deadline |
| Retryable Ledger send broadcast failure | Report as pending, not failed; recovery resends |
| Expiry or rejection found during recovery | An app-wide toast says it was not sent; swap and pay show expiry by the intent deadline |
| Swap or pay request that must be rebuilt for capacity or format | Leaving the overlay removes the unsent intent so Activity stops offering it |

The recovery host runs on unlock and sync changes; it is not a background
signing worker. Signed data is bound to a network and account, and the same
operation is never broadcast twice. Voting and migration use their own durable
workflows, not this send outbox.

Sources: [signed operation database](../rust/src/wallet/ledger/operations.rs),
[recovery host](../lib/src/features/ledger/services/ledger_operation_recovery.dart), and
[send broadcast](../lib/src/features/send/services/send_flow.dart).

## App and SDK versions

| Component | Current | Recheck on update |
| --- | --- | --- |
| Ledger Zcash app | Minimum `3.9.3` | Installable version per model and OS, normal signing, migration canary |
| Apple Bluetooth transport | `hw-transport-ios-ble` 1.0.1 (`4df8fff21c1738a1dff4d2ee19175dd3263d6c5f`) | Discovery, app switching, cancelling and draining an in-flight exchange |
| Android Ledger Mobile DMK | `io.github.ledgerhq:device-management-kit:0.0.4` | Nullable device name, connection teardown, late responses, minimum Android |
| Windows and Linux Bluetooth | Vizor's own adapters | GATT and pairing, Ledger framing and MTU, cancellation and late responses, OS, adapter, and model compatibility |
| Device app SDK | app-zcash 3.9.3 builds with `ledger_device_sdk` 1.37.0 | `0x6901` during review and the post-signing status screen; unrelated to the mobile DMK version |

Versions compare as `major.minor.patch`. Being at 3.9.3 or later does not verify
every new behavior, and the known migration guard stays separate from the
version check.

The upstream release [PR #40](https://github.com/LedgerHQ/app-zcash/pull/40)
merged on 2026-09-08 with source `22dc38537f9a84b31b938e3ca95434595ef378d3`. When
checked on 2026-09-14, Ledger's app catalog listed 3.9.3 on the default Ledger
Live provider for Nano S Plus (OS 1.6.1), Nano X (2.7.1), Stax (1.10.1), Flex
(1.6.1), and Apex P (1.1.1), last modified 2026-09-08. Version 3.9.2 was only on a
non-default provider. This shows 3.9.3 is published; it does not show that
every model and OS pairing was tested with Vizor. Ledger documents the Mobile
DMK as alpha, so using it is no stability guarantee.

Sources: [Dart minimum version](../lib/src/features/ledger/ledger_capability.dart),
[Apple pin](../ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved),
[Ledger Mobile SDK documentation](https://developers.ledger.com/docs/device-interaction/dmk-kmp),
[Zcash app changelog](https://github.com/LedgerHQ/app-zcash/blob/22dc38537f9a84b31b938e3ca95434595ef378d3/CHANGELOG.md), and
[Ledger app catalog](https://manager.api.live.ledger.com/api/applications).

## Verification status

### By platform

| Combination | Verified | Not yet verified |
| --- | --- | --- |
| Windows USB | Implemented and built in the Release (`c37c9c150`) | Per-scenario results on a device |
| Windows Bluetooth | Windows 11 ARM64 VM, x64 Release, USB Bluetooth dongle, Stax: connection, app readiness, wallet identity, UFVK import, duplicate index; user reported a successful transaction and working rejection, cancel, and reconnect | Other models and adapters, Windows 10, TEX, shield, swap, pay, and voting individually |
| Linux USB | Ubuntu 24.04 x86_64 VM Release, Stax HID access after installing the udev rule; user confirmed a transaction | Per-feature and recovery scenarios; a USB re-send on the final Bluetooth build |
| Linux Bluetooth | Same VM with Stax: pairing, import, Bluetooth enrollment of a USB account; user confirmed connection and signing; pairing through Vizor's agent with code confirmation completed end to end | Other distributions, adapters, and models; per-feature and recovery scenarios |
| macOS USB and Bluetooth | Not rerun on a device during this work | Single device, app switching, cancellation, TEX double approval, first pairing, reconnect, fallback before the operation starts |
| iOS Bluetooth | Not rerun on a device | First-time and denied permission, app switching with the link kept or lost, cancelling a pending exchange, returning from background |
| Android Bluetooth | Synthetic probe only | API 30 location and API 31+ Bluetooth permissions, rediscovery, GATT teardown failure, reconnect after an exception |
| Wallet Link | Real client encryption and decryption, transfer model, provider, and UI tests with mocked Rust and relay | A real desktop QR, mobile import, and Bluetooth signature |
| Each supported model | Stax only | Normal signing, rejection, consecutive approvals, and maximum capacity per model |

User-confirmed results are recorded as reported. Transaction IDs and
confirmation counts were not captured in this document.

### What each kind of evidence covers

| Evidence | Covers | Does not cover |
| --- | --- | --- |
| Dart service and widget tests | Capability, retries, recovery, screen transitions, mocked responses | Device firmware, real Bluetooth, OS permissions |
| Rust unit tests | APDU, PCZT, account, and signature checks; signed operation states | USB or Bluetooth radio, real approvals, broadcast |
| Speculos integration scenarios | App flows against the firmware emulator | Physical USB or Bluetooth and OS combinations; mobile replaces the Bluetooth service with an HTTP adapter |
| Android native probe | Unchanged handler, official DMK, emulator Bluetooth, synthetic peer | Real firmware, RF, the Flutter engine, signing and broadcast |
| Apple XCTest | Protocol parsing and the app-switch coordinator | Real `BleTransport` callbacks, permissions, draining a pending exchange |
| Linux fake BlueZ and native tests | Discovery, pairing agent, split APDUs, cancellation, reconnect, write type over real GIO calls on a test D-Bus | A real adapter and Ledger |

The [Android probe record](../scripts/ledger-ble-probe/README.md) holds
observations from 2026-09-07 against a synthetic peer. Its timings come from
those runs, not from the current implementation. It observed normal paths, some
recovery, a late response, and the nullable-name failure; the handler now
contains that exception and confirms GATT and session teardown, which is not
proof that every timing is fixed on real devices.

### Open issues

- **Balance not refreshed after leaving a failed Ledger send.** On desktop,
  after a connection failure the user leaves review. The proposal lock is
  released, but the spendable balance is not re-read, so `Insufficient shielded
  balance` can remain until the next sync. A read-only database check showed the
  funds intact and unlocked. `_scheduleDiscard` in
  [send review](../lib/src/features/send/screens/send_review_screen.dart) and
  `discardSendProposal` in [send flow](../lib/src/features/send/services/send_flow.dart)
  do not request a refresh. The likely fix is to refresh after a successful
  discard. Reproduced only on a desktop Ledger send.
- **Receive-address verification on the device** needs a product decision. It
  would need a contract that shows the same account, index, and receiver as
  Vizor's address rotation.
- **Four shielded display outputs.** The upstream
  [PCZT contract](https://github.com/LedgerHQ/app-zcash/blob/22dc38537f9a84b31b938e3ca95434595ef378d3/docs/PCZT_APDU.md)
  shows at most 4 shielded outputs, and Vizor has no host-side pre-check. Sends
  are single-payment today, so this blocks nothing now; add the check before
  multi-output sends.
- **Android API 30 floor.** It applies to every Vizor Android user and belongs
  in the release OS policy.
- Apple Nano Gen5 Bluetooth and mobile USB stay unsupported unless the scope changes.

### Upstream changes to watch

- ledger-secure-sdk [#1701](https://github.com/LedgerHQ/ledger-secure-sdk/pull/1701),
  open: answers any APDU sent while another is pending with `0x6901`. Vizor
  already keeps one pending APDU per device and retries `0x6901`.
- device-sdk-ts [#1884](https://github.com/LedgerHQ/device-sdk-ts/pull/1884),
  open: maps `0x6901` to a typed DMK error.
- ledger-secure-sdk branch `abo_usb_optim`, no PR and disabled by a flag: sends
  short USB HID packets without 64-byte padding. Recheck the HID reader if it
  ships.

### Before release

- Record the installed Zcash app version, device OS, model, and Vizor commit together.
- On every OS and device the release names, run import, signing, validation, and broadcast to a result.
- Include app switching, cancelling during UFVK approval, rejecting a signature,
  Bluetooth loss, reconnecting, and outbox recovery after an app restart.
- Do not count Apple's pending exchange or Android's GATT and session cleanup as
  passed on mock tests alone.
- Recheck consecutive Ledger signatures after the account-level cleanup, including the 4-second status-screen wait.
- Keep the Orchard-to-Ironwood guard until an upstream fix and the zero-value
  padding canary both pass.
- When the support matrix changes, update the capability, user guidance, UI
  entry points, tests, and this document together.

## Appendix: verification history

Automated counts belong to their round and do not add up to a full suite result
at the current head.

| Date | Commit | Scope | Automated checks | Device checks |
| --- | --- | --- | --- | --- |
| 2026-09-09 | `0e66e86bc` | First review of this contract | Flutter 110 passed (common 56, mobile UI 37, adjacent 17); Rust 70 passed (Ledger 62, selector 8) | None |
| 2026-09-09 | `e16e3af39` | UFVK and PCZT share one cancellable native request on Apple and Android | Dart 43 and 18 passed; Apple XCTest 19; Android native 4 | None |
| 2026-09-09 | `f4c4c4ae3` | Ledger accounts in Wallet Link | 105 passed; 16 files analyzed; mobile capture checked | No QR-to-Bluetooth signature |
| 2026-09-09 | `c37c9c150`, `6a313d06f` | Windows USB and Bluetooth | Dart 97 passed; 15 files analyzed; C++/WinRT compile and protocol test | Stax over Bluetooth: import and duplicate index; user reported a transaction and recovery paths |
| 2026-09-09 | `796d2a60e` | Linux USB | Dart 55 passed | `hidraw` was root-only until the udev rule; readiness misread the denial as a rejection (fixed); user confirmed a transaction |
| 2026-09-10 | `0c7473072` | Linux Bluetooth | Dart 94 passed; fake BlueZ on a test D-Bus; shared protocol C++ | Stax pairing, import, Bluetooth enrollment; writes needed `WriteValue` type `request`; user confirmed signing |
| 2026-09-10 | `11e570282`, `e0ce7858e`, `9af211630` | Linux pairing agent and code confirmation | Native handler and transport tests on the VM's real GIO and D-Bus | Stax: code confirmed within the window, pairing finished in about 5 s, UFVK read, next index suggested; an earlier attempt confirmed after the window and failed on the Ledger |
| 2026-09-10 | `dff30debc`, `bee896046`, `9eac24cae` | Shielding in rounds | Shield overlay tests for extra rounds and both pause cases | None |
| 2026-09-14 | `2cdbd5552` | 4-second wait before any command after signing | Rust Ledger 64 passed; Dart Ledger tests 136 passed, 1 skipped | Windows VM x64 Release built and launched; no Ledger operation |
| 2026-09-16 | Working tree based on `7ef833bc0` | Independent accounts; remove wallet fingerprint and grouping; show Advanced account paths | Desktop regression 166 passed, 1 mobile-only skip; mobile regression 65 passed plus the skipped provider test passed in its mobile lane; mobile gallery and Wallet Link follow-up 29 passed; Rust Ledger 62, keys 45, API 2 passed; Flutter analysis clean; FRB regenerated | Desktop/mobile widget captures checked; no physical Ledger signing or native release build |
