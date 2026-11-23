# Keystone signing E2E

Run a command from the repository root on macOS. The iOS target needs a
dedicated, booted simulator. The default macOS run uses a hidden desktop window.

```sh
FLUTTER_DEVICE=macos scripts/e2e/flutter-keystone.sh
FLUTTER_DEVICE=macos scripts/e2e/flutter-keystone.sh --gui
FLUTTER_DEVICE="$SIMULATOR_UDID" scripts/e2e/flutter-keystone.sh
```

Both targets exercise the signing screens for their own form factor.

| Scenario | Firmware exchange | Required outcome |
| --- | --- | --- |
| TEX payment | Two consecutive full PCZT approvals | The Zebra mempool is empty before each approval. Both expected txids appear in mined blocks and the child spends the parent. |
| Ordinary payment to a transparent address | One compact batch approval | The send receipt shows success and the expected txid appears in a Zebra block. |
| Voting delegation | One compact batch of two SDK bundles | Both bundle memos can be reached. Each stored signature verifies against the original bundle's randomized key and sighash. |

The runner needs FVM, Xcode, CocoaPods, Rust, Python 3, jq, Docker Compose and
grpcurl. It builds two host signers from Keystone Cypherpunk firmware 3.2.2
with the public Speculos fixture seed. Voting uses the stock signing code. Payments
use an isolated build patched for regtest account derivation and consensus
parameters. Set `KEYSTONE_FIRMWARE_DIR` to reuse a clean checkout of the pinned
revision. The default is `~/keplr-workspace/refs/keystone3-signer-check`.

For payments, the runner starts a fresh Zebra regtest with lightwalletd, funds
the firmware account before and after Ironwood activation and matures the
coinbase outputs. The test logs each expected txid, block hash and height.
The runner removes its Compose project and volumes on exit. To change the
default loopback ports, set `NU7_REGTEST_RPC_PORT` (49242) and
`NU7_REGTEST_LIGHTWALLETD_PORT` (49177).

## Scanning with the Keystone GUI

On Apple Silicon macOS, `--gui` runs the same three desktop tests and opens
Vizor and the Keystone 3.2.2 SDL simulator for each signing request. Install CMake and SDL2
(`brew install cmake sdl2`). Keep the primary display unlocked with room for
both windows and grant Screen Recording permission to the process macOS
prompts for. The runner provisions separate payment and voting simulator wallets with the
public Speculos mnemonic. The payment GUI uses the same regtest firmware
archive as the payment signer. The voting GUI uses the stock archive.

The driver enters the fixture PIN and clicks **Scan**. Keystone reads the
animated QR from the desktop through its own screen reader. The test checks
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
passes each image to its native macOS `mobile_scanner` barcode detector and
feeds the detector's event to the active scan screen. The scan screen must
reconstruct the response before the test checks the transaction on Zebra or
verifies both voting signatures against their original randomized keys and sighashes.
The PNGs supply the camera input in this lane.

The GUI server has no host signer configured. The runner uses the host tools
to export fixture account information during setup. Default desktop and iOS
tests use the host signers and supply the returned URs to the barcode callback.
Physical camera optics and ballot submission require separate verification.
