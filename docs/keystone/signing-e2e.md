# Keystone signing E2E

Run either command from the repository root on macOS. The iOS target needs a
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

## Scanning the voting QR with the Keystone GUI

On Apple Silicon macOS, `--gui` runs the same three desktop tests and opens
Vizor and the Keystone 3.2.2 SDL simulator for voting. Install CMake and SDL2
(`brew install cmake sdl2`). Keep the primary display unlocked with room for
both windows and grant Screen Recording permission to the process macOS
prompts for. The runner initializes a fresh simulator wallet in its temporary
directory using the same public Speculos mnemonic as the host signer.

The driver enters the fixture PIN and clicks **Scan**. Keystone reads the
animated QR from the desktop through its own screen reader. The test checks
the captured Keystone window for **Confirm Transaction (1/2)** with macOS
Vision. Every observed UR frame must belong to the current request. Only
those observed frames go to the voting signer, and both returned signatures
must verify against the SDK bundles. A missing review or incomplete scan
fails the test.

The default desktop and iOS runs pass outbound URs from the widget to the
host signer. Payments use that exchange in all modes. Signed responses enter
Vizor through its barcode detection callback. Physical camera optics and
ballot submission require separate verification.
