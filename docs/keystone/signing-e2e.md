# Keystone signing E2E

Run from the repository root on macOS with Docker running and the primary display
unlocked. Both targets open the Keystone GUI for every signing request.

```sh
FLUTTER_DEVICE=macos scripts/e2e/flutter-keystone.sh
```

For iOS, boot a dedicated iPhone in Simulator and use its UDID from the list.

```sh
xcrun simctl list devices booted
FLUTTER_DEVICE="<booted iPhone UDID>" scripts/e2e/flutter-keystone.sh
```

| Scenario | Firmware exchange | Required outcome |
| --- | --- | --- |
| TEX payment | Two consecutive full PCZT approvals | After each GUI approval, the Zebra mempool is empty when Vizor opens its scanner, before it reads the signed QR. Both expected txids appear in mined blocks and the child spends the parent. |
| Ordinary payment to a transparent address | One compact batch approval | The send receipt shows success and the expected txid appears in a Zebra block. |
| Voting delegation | One compact batch of two SDK bundles | Both bundle memos can be reached. Each stored signature verifies against the original bundle's randomized key and sighash. |

The runner needs FVM, Xcode, CocoaPods, Rust, Python 3.9 or later, jq, Docker Compose and
grpcurl. It builds separate voting and payment GUI simulators from Keystone Cypherpunk firmware 3.2.2
with the public Speculos fixture seed. Voting uses the stock signing code. Payments
use an isolated build patched for regtest account derivation and consensus
parameters.

By default the runner clones firmware 3.2.2 into
`~/keplr-workspace/refs/keystone3-signer-check` on first use. To use a different
location, set the checkout path before running either command above.

```sh
export KEYSTONE_FIRMWARE_DIR="$HOME/src/keystone3-firmware"
```

The runner creates the checkout if missing. An existing checkout must be at
`f74496eedd0978a0de5c43fefd8291b201674e8e` with clean tracked files. Relative
paths resolve from the Vizor repository root. The runner creates and removes
temporary build checkouts beside the selected firmware checkout, so its parent
directory must be writable.

For payments, the runner starts a fresh Zebra regtest with lightwalletd, funds
the firmware account before and after Ironwood activation and matures the
coinbase outputs. The test logs each expected txid, block hash and height.
The runner removes its Compose project and volumes on exit. To change the
default loopback ports, set `NU7_REGTEST_RPC_PORT` (49242) and
`NU7_REGTEST_LIGHTWALLETD_PORT` (49177).

## Scanning with the Keystone GUI

The iOS Simulator and macOS runs open the Keystone 3.2.2 SDL
simulator for every payment and voting request. Install CMake and SDL2
(`brew install cmake sdl2`). Keep the primary display unlocked with room for
both windows and grant Screen Recording permission to the process macOS
prompts for. The runner provisions separate payment and voting simulator wallets with the
public Speculos mnemonic. The build exports each simulator fixture’s public account as a pairing UR for Vizor.

The driver enters the fixture PIN and clicks **Scan**. Keystone reads the
animated QR with its own image detector. On macOS the camera source is the
primary display. On iOS the runner supplies the selected simulator’s rendered
display via `simctl io screenshot`, independent of other simulator windows. The test checks
the captured Keystone window with macOS Vision. A completed review shows the
expected title, amount, fee and a ZEC value.

| Request | Expected review | Required outcome |
| --- | --- | --- |
| TEX parent, then child | **Confirm Transaction** for each full PCZT | Both txids are mined and a child input references the parent txid. |
| Ordinary payment | **Confirm Transaction** for the single-item batch | The txid is mined. |
| Voting | **Confirm Transaction (1/2)**, then **(2/2)** after **Next** | A single batch approval produces the response QR. Both persisted signatures verify against their respective SDK bundles. |

Every observed request frame must belong to the current request. After the final review,
the driver swipes the approval slider and enters the fixture PIN on the
Keystone review screen. The simulator signs and displays its response QR.
The loopback service captures PNGs of that window while it is open. Vizor
decodes those pixels inside the app. macOS uses the native `mobile_scanner`
image analyzer. The plugin disables that analyzer on iOS Simulator, so the
iOS test app uses ZXing and sends its detections to the active scanner stream. The scan screen must
reconstruct the response before the test checks the transaction on Zebra or
verifies both voting signatures against their original randomized keys and sighashes.
The PNGs supply the camera input in this lane.

Physical camera optics and ballot submission require separate verification.
