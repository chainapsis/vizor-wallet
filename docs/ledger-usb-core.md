# Ledger USB device protocol

C01 in the [Ledger core review plan](ledger-pr-plan.md), extracted from
`fbe51859972213eb0c70dc80bda67c7ef7f249e8`. This slice exposes device operations;
it does not add an onboarding screen, import an account into the wallet database,
or sign/broadcast transactions.

## API and behavior

| Rust bridge API | Behavior |
| --- | --- |
| `ledger_device_app` | Open a fresh USB session and read the current app name/version. |
| `ledger_open_zcash_app` | If needed, close another app, observe the dashboard, open Zcash, reconnect and verify the app name. |
| `ledger_export_account` | Request the selected account's UFVK and import metadata after device approval; reject non-mainnet requests before device access. |
| `ledger_cancel_operation` | Cancel the current generation of host-side device work. |

The UFVK request encodes `m/32'/133'/account'` and
`m/44'/133'/account'`. Valid account indexes are `0..2147483647`.
Responses carry status words and a length-prefixed UTF-8 payload; truncation,
oversize data, empty continuation and trailing bytes are errors. The framing
limit is 8 KiB including the length prefix. Account import and semantic UFVK
validation belong to C02.

The importer never requests seed material through these APIs. A viewing key is
still sensitive because it enables wallet-history inspection; the API returns it
to its caller without logging or persisting it.

C02 added `ledger_export_account`. C03 removes the superseded string-only
`ledger_export_ufvk` bridge, which had no application callers. The lower-level
Rust `get_ufvk` helper remains for the planned diagnostic/canary consumers.

## USB lifecycle

- All desktop platforms require Ledger HID vendor ID `2c97`. macOS and Windows
  require usage page `ffa0`; Linux selects interface 0. The first matching device
  is used; there is no multi-device picker.
- Device operations serialize through one mutex and open fresh HID sessions.
  Closing or opening an app reconnects because USB may disappear during a switch.
- An active operation has a five-minute budget, with 100 ms HID read polling to
  observe cancellation. Waiting for the operation mutex is outside that budget.
- App-switch observation uses a ten-second polling budget, subject to the
  enclosing device exchange deadline; this is not a strict wall-clock timeout
  for every OS/driver call.
- Cancellation stops host continuation/retry work. It does not dismiss a prompt
  already displayed on the Ledger or guarantee interruption of a native HID call.
- Cancellation targets the currently active Rust operation. It has no caller
  token, does not cancel a queued request, and is a no-op before a request becomes
  active. C03's caller coordination must prevent overlapping user intents.
- The cancellation bridge is synchronous and only updates atomic state. It does
  not enter the device-operation mutex or wait for an FRB worker, so a busy worker
  pool cannot defer cancellation until a later operation becomes active.
- A new operation uses a new generation. A previous cancellation must not cancel
  the next request. Locked/rejected/not-installed device errors remain explicit.
- The existing bounded `0x6901` retry policy retries only the rejected exchange.
  It does not replay successful commands or automatically retry user rejection.

Apple sandbox entitlements grant USB access for Debug/Profile and Release.
Bluetooth permission and native BLE handlers are outside C01. iOS/Android do not
receive HID dependencies; device APIs return unsupported-platform errors there.
App-version readiness policy and higher-level transport selection belong to C03.

## Linux setup

The Linux build needs `libudev-dev` for the HID backend. The repository development
container declares this dependency. Runtime access uses the active local session's
`uaccess` ACL, not root execution or world-writable HID permissions.

An administrator can install the included rule and reconnect the Ledger:

```sh
sudo install -m 644 linux/udev/20-vizor-ledger.rules /etc/udev/rules.d/20-vizor-ledger.rules
sudo udevadm control --reload-rules
```

The build does not install this rule automatically. Missing-device, access-denied,
device-in-use and interrupted-connection failures remain distinct. Headless/SSH
sessions without a local active graphical login are not covered by this rule's
session-access contract.

## Deliberate difference from the source snapshot

The source's USB UFVK loop checked its 8 KiB limit only after collecting the
declared number of bytes, and an empty successful continuation could wait until
the operation deadline. C01 validates the initial length before requesting more
data and rejects an empty continuation immediately. It also checks cancellation
after a blocking exchange, so a response that arrives during cancellation cannot
surface as success. Tests exercise the exchange loop, not only the final decoder,
to show that these failures issue no further continuation commands.

Other source behavior is preserved within this device-only scope. PCZT parsing,
signing, account fingerprint metadata, database writes, signed-operation recovery
and UI entry points remain in later review units.

## Validation boundary

Focused tests cover protocol encoding/decoding, bounded UFVK collection, device
app responses, generation cancellation and deadlines. Hardware-free tests do not
establish physical-device import success, USB permissions on another OS, or
transaction signing. The PR records the exact build/test commands run on its
head and explicitly lists unverified platforms and physical-device behavior.
