# Voting validation and regtest

Use when planning or explicitly running voting-chain integration verification.

## Participation validation

The JSON fixtures in `rust/tests/fixtures/voting-participation` contain public
mainnet/stage signed headers, validator sets, and actual membership/non-membership
proofs. Tests use each fixture header's timestamp, so they remain deterministic.
Corruption tests cover signatures, validator power, app hash, query key/height,
proof bytes, value, wrong network and stale/future headers. Deterministic signed
headers also cover partial validator replacement, changed powers, both strict
quorum boundaries, forged validator addresses and duplicate signers. No private wallet
material is included.

## Mobile reinstall regtest E2E

Run `scripts/e2e/flutter-ios-regtest-mobile-voting-reinstall.sh` with an explicit
`SIMULATOR_UDID` when multiple simulators are booted. The existing mobile voting
runner also asserts that a fully completed vote removes its Home card and
persists the confirmed hidden decision. Before voting it checks unused note
observations on disk; after delegation it checks that used observations persist.

The reinstall runner keeps the same Zcash and vote chain alive between two
Flutter integration invocations. Phase one imports, syncs and votes through the
real mobile UI. The host verifies the app is uninstalled after Flutter test cleanup,
explicitly uninstalling it if the Flutter runner leaves it installed. Phase two asserts the old DB/sidecar are absent, clears only
the regtest app's surviving secure storage, and imports the same mnemonic from
birthday 1. The test checks that the ordinary voting-cache directory is absent
before cleanup, rather than inspecting an obsolete secure-storage key. No
database, voting hotkey, progress or participation cache is copied.

Tests configure transport/source support and the newly created local chain's
trust anchor. They do not override eligibility, participation, Home visibility,
or cryptographic verification. The regtest anchor is immutable for that process
and is never consulted for mainnet/testnet. The gateway relays actual CometBFT
proofs and records aggregate request counts without logging queried identifiers.

The restored Home assertion requires an active round in the actual cached list,
a synced snapshot, verified used notes, no remaining voting rights and no local
recovery state. It then asserts the card is absent, checks Settings/detail access,
and checks that Home reentry does not repeat participation RPCs. Request counts
are compared against the start of the restore phase so first-phase requests
cannot satisfy the restored-check assertion. Both unused and used observations
are reevaluated with a fresh client and a forced check, proving disk reuse without
additional participation RPCs. Initial hidden UI alone never satisfies the test:
it requires a confirmed hide decision. Screenshots are
saved under `.regtest-voting/logs/screenshots/`.

Home participation work stops at asynchronous boundaries when Home is left or
the app backgrounds. An already dispatched request may finish; subsequent
requests, evaluation and remaining rounds are skipped. A new Home visit gets a
new scope, while explicit detail checks remain independent of Home visibility.
Round details are retained in memory per network/config/account/round only while
waiting for snapshot sync, avoiding repeated detail requests during that wait.
Manual retries fetch fresh details.

Within one participation check, a transient HTTP failure retries only that request
once after 300 ms. Successful responses and the selected proof height are retained.
Permanent HTTP errors, malformed data and failed proof verification are not retried
inside the operation. The four-minute budget and Home cancellation still apply;
a final failure falls back to the coordinator's exponential backoff.

When preparation finds no unknown snapshot notes, no participation RPC is sent.
Rust rereads the wallet and reevaluates the same candidate fingerprint using
locally stored observations. The existing local result/persistence path still runs; zero notes never
means previously used voting rights. It confirms a hidden Home decision when
there is no actionable local recovery.

## Home discovery regtest

`scripts/e2e/flutter-ios-regtest-mobile-voting.sh` verifies a confirmed visible
Home card before voting, mines 20 additional Zcash blocks, and drives the real
sync engine. The test rejects any false visibility-provider transition and
checks the rendered card on every pumped frame, including at least one syncing
frame. It requires a newer scanned height and sync completion, and no additional
participation RPCs. Screenshots are saved as `home-during-resync.png` and
`home-after-resync.png` under `.regtest-voting/logs/screenshots/`.
The same flow then completes voting and checks that Home hides the card; the
reinstall runner also includes this pre-vote resync check.

## Related changes

Run regtest only when explicitly requested; follow [the E2E guide](../../../scripts/e2e/README.md).
