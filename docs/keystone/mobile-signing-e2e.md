# Mobile Keystone signing E2E

On macOS, boot a dedicated iOS simulator. Run from the repository root with its UDID:

```sh
FLUTTER_DEVICE="$SIMULATOR_UDID" scripts/e2e/flutter-mobile-keystone.sh
```

The runner needs FVM, the iOS build toolchain, Rust, Python 3 and jq. It builds
the Cypherpunk Rust library from Keystone firmware 3.2.2. The checkout defaults
to `~/keplr-workspace/refs/keystone3-signer-check`. Set `KEYSTONE_FIRMWARE_DIR`
to reuse a clean checkout of the pinned revision.

The firmware exports account 0 as an animated Zcash account UR using the public
Speculos fixture seed. The wallet imports that account and scans a synthetic
Ironwood note. Each send scenario starts with a fresh copy of the funded wallet.

| Mobile scenario | Firmware exchange | Required outcome |
| --- | --- | --- |
| TEX payment | Two consecutive full PCZT requests | Zero submissions before the second approval, then two submissions to loopback lightwalletd and the send success screen |
| Ordinary payment to a transparent address | One compact batch request | Zero submissions before approval, then one submission to loopback lightwalletd and the send success screen |
| Voting delegation | One compact batch containing two SDK bundles | Both bundle memos are accessible. The two signatures are decoded in order, stored together, read back and verified against each original bundle's randomized key and sighash |

The test reads UR frames from each signing screen and passes the firmware's
response through the app's UR decoder and scanner callback. Voting starts with
the SDK's prepared delegation requests and ends with verified signatures.
Ballot submission, chain confirmation and physical camera scans have separate
verification paths.

## Zebra regtest

```sh
FLUTTER_DEVICE="$SIMULATOR_UDID" scripts/e2e/flutter-mobile-keystone.sh --zebra
```

This mode also needs Docker Compose and grpcurl. It builds a host-only signer
with regtest derivation, starts a fresh Zebra chain and funds the firmware
account on both sides of Ironwood activation. It runs the two send scenarios.
For each expected txid it mines blocks, checks the block transaction list and
prints the block hash and height. It also verifies that a TEX child input
spends its parent. The runner removes its Compose project and volumes on exit.

The default loopback ports are 49242 (Zebra RPC) and 49177 (lightwalletd).
Set `NU7_REGTEST_RPC_PORT` and `NU7_REGTEST_LIGHTWALLETD_PORT` to use other
available ports.
