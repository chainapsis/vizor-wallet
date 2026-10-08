# Zodl gift-link compatibility

Vizor accepts native Zodl gift links through explicit in-app card-link paste and
gift-card QR scanning. External URL dispatch remains Vizor-only: this change adds
no Android app-link host, iOS associated domain, or external-intake route.

## Wire format

The compatibility target is the native gift-link implementation in
[Zodl's Android SDK source at 7279656](https://github.com/zodl-inc/zodl-android-wallet-sdk/blob/7279656d7de2a3ebf593b7e4e600bffc0e2cd68f/backend-lib/src/main/rust/liberated_payment.rs).
This is not a claim of conformance to every draft of ZIP 324. Vizor implements
the format using its existing Rust wallet libraries, without a Zodl SDK dependency.

The accepted origin is `https://gift.zodl.com/`, with fragment fields
`v=1&key=<Bech32m key>&height=<birthday>`. Required fields must occur exactly
once. The key contains 32 bytes of BIP39 entropy; its HRP is `zgift`,
`zgifttest`, or `zgiftregtest`. The resulting English mnemonic uses the empty
BIP39 passphrase and ZIP 32 account zero. Existing network gates still apply:
production supports mainnet, and regtest remains explicitly enabled by the
existing development configuration. Testnet links cannot be redeemed on mainnet.

Birthdays must be positive canonical integers, at or after NU5 on mainnet/testnet,
and no later than the currently observed tip when inspected. The decoded key and
link never appear in parser errors.

Optional `amount` and `desc` are informational. Missing, malformed, or repeated
optional fields do not invalidate the bearer key. Amounts use ZEC with at most
eight fractional digits. Descriptions use percent-encoded UTF-8, preserve literal
`+`, and are limited to 512 decoded bytes; control and bidi formatting characters
are removed before display.

## Redemption and recovery

Native cards use an isolated claim wallet and the ordinary full birthday-to-tip
scan. They do not use Vizor's Ironwood funding observer, which depends on
Vizor-issued cards. Old birthdays use the existing long-sync confirmation UI.

The reviewed recipient amount is the actual maximum spendable balance after
transaction fees. The link's advertised amount never caps or authorizes a spend.
Cards with no advertised amount display an unknown amount until inspection.
The amount is re-estimated for the destination and checked again before signing;
a changed amount requires another inspection.

External funding uses Vizor's ordinary confirmation policy (six for untrusted
funds), rather than the two-confirmation policy for Vizor-issued cards. The claim
discards the outgoing viewing key so possession of the gift key does not disclose
the recipient through outgoing note recovery.

Durable claim records preserve the original native URI and store the verified
recipient amount separately. They retain the native sweep policy after restart
and use the existing submission, rebroadcast, transaction-evidence, and
confirmation-based secret-cleanup paths. An unresolved zero amount may be saved
as a pending card, but cannot begin submission.

A refilled native card can be claimed again after the prior claim finishes its
six-confirmation recovery and secret cleanup. Submission journals a new amount,
submission time, bearer link, and transaction baseline before broadcasting. The
card list shows the latest attempt; earlier transactions remain in wallet activity.
Opening a preview does not replace a completed receipt or restore its secret.
New-wallet setup recovery also preserves the native link and inspected amount.

Each native scan has one endpoint-fallback owner. Lifecycle cancellation stops
fallback dispatch as well as preventing a late scan result from reaching the UI.

Vizor's existing issuance format and v1/v2/v3 redemption behavior are unchanged.

## Verification

`rust/tests/zodl_gift_claim.rs` exercises the public Rust APIs with a real
temporary SQLite wallet. It decodes the Zodl encoder vector, scans encrypted
Orchard compact blocks, checks the five/six-confirmation boundary, and verifies
multi-deposit max-spend amounts with ZIP-317 fees. It also checks rejection of a
stale reviewed amount after another deposit matures, input-lock cleanup, and the
stored Discard-OVK policy's rejection of hardware PCZT signing. This test does
not generate proofs, broadcast transactions, contact RPCs, or launch an app.

Run it from `rust/`:

```bash
cargo test --locked --offline --test zodl_gift_claim
```

## Verification limits

Parser vectors, mocked wallet-service tests, restart recovery, in-app UI tests,
and external-intake rejection cover the local contract. A funded card generated
by a released Zodl app has not yet been redeemed end to end on Android or iOS.
