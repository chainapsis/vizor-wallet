# Delegation signing transaction (TX1)

## Status and scope

This document specifies the Zcash transaction that a wallet constructs for
delegation signing. In this document it is called the **delegation signing
transaction**, or **TX1**.

TX1 has the structure and signature digest of a normal Zcash transaction. It
is represented as a PCZT so that either wallet software or a hardware wallet
can produce an Ironwood SpendAuth signature using the normal Zcash signing
path.

TX1 is not the vote-chain delegation submission. The two artifacts have
different lifecycles:

```text
Zcash transaction domain                     Vote-chain domain

build TX1 PCZT
    |
    +-- ZIP-244 shielded sighash
    |       |
    |       +-- SpendAuth signature
    |                  |
    +------------------+--------------------> delegation submission
                                               + ZKP #1
                                               + rk
                                               + TX1 sighash
                                               + SpendAuth signature
```

The current TX1 is deliberately **not broadcastable on Zcash**. Its input is
the signed synthetic note with a synthetic authentication path, and the PCZT
is not completed with an Ironwood proof, binding signature, or transaction
extraction. "Normal Zcash transaction" therefore means that TX1 uses the
normal transaction structure and ZIP-244 signing algorithm. It does not mean
that the resulting bytes can or should be submitted to the Zcash network.

An implementation MUST NOT submit either the unsigned or signed TX1 PCZT to a
Zcash node.

## Goals

TX1 provides:

- a standard PCZT input for existing Zcash signers;
- proof that the holder authorized the delegation with the Orchard/Ironwood
  account SpendAuth key;
- binding to one voting round, one delegated note bundle, and one voting
  hotkey; and
- separation between the wallet spending key and the software-managed voting
  hotkey used after delegation.

TX1 does not transfer the holder's real ZEC and does not consume the real
notes whose voting weight is delegated.

## What TX1 authorizes

TX1 is logically a delegation of voting rights from the Zcash account to one
new voting hotkey. The wallet generates that hotkey separately from the
account spending key, then uses the hotkey's one external Orchard address in
both the VAN and TX1.

For one voting identity and round, the wallet SHOULD generate one fresh
hotkey before preparing delegation bundles. If the eligible notes require
more than one bundle, every TX1 for that identity and round SHOULD delegate to
the same hotkey.

No single field carries the full meaning of the delegation. The authorization
comes from the following bindings taken together:

1. ZKP #1 proves that the real eligible notes belong to the same account that
   owns the synthetic note spent by TX1.
2. `rho_signed` binds that synthetic note to the eligible-note commitments,
   the VAN, and the voting round.
3. The VAN commits to one hotkey address, the delegated weight, and the round.
4. TX1 creates its zero-value output at that same hotkey address, and ZKP #1
   reconstructs the output commitment as `cmx_new`.
5. The account's SpendAuth signature authorizes the resulting TX1 sighash.

Consequently, a valid delegation signature and ZKP #1 statement mean:

> The account that owns these eligible notes delegates their voting weight
> for this round to this one new hotkey.

The hotkey can authorize later vote-chain actions. It cannot spend the
account's Zcash funds.

## Inputs

The wallet MUST fix the following inputs before building TX1:

| Input | Requirement |
| --- | --- |
| Network | The network stored for the voting round. |
| Snapshot height | The height at which eligible notes and witnesses were selected. |
| Consensus branch ID | The branch active at the snapshot height. It MUST match the network and height. |
| Account FVK | The 96-byte Ironwood-capable full viewing key for the account that owns the eligible notes. |
| Seed fingerprint | The ZIP-32 fingerprint used by an external signer to select the correct seed. |
| Account index | The ZIP-32 account index for the spending key. |
| Voting hotkey address | A valid 43-byte raw Ironwood address on the same network. |
| Voting round ID | Exactly 32 bytes, represented by this crate as 64 hexadecimal characters. |
| Eligible note slots | One to five real notes, padded to `BUNDLE_NOTE_SLOTS` with the circuit's synthetic padding notes. |
| VAN commitment | The commitment to the voting hotkey, delegated weight, round, and blinding factor. |
| Round name and weight | Display-only memo data. |

The account FVK, account index, seed fingerprint, network, selected notes,
padding secrets, voting hotkey, and voting round ID MUST be taken from the same
persisted delegation-bundle context. A wallet MUST NOT allow an external
signer response to replace any of these values.

## Notes used by TX1

There are three different kinds of notes in the construction:

- **Eligible notes** are the holder's real Zcash notes at the voting snapshot.
  They are witnesses to ZKP #1 and are not spent by TX1.
- **Padding notes** fill ZKP #1's fixed five-note input. They are synthetic,
  and TX1 does not spend them.
- The **signed note** is one additional synthetic note created only as TX1's
  spend. Its constrained `rho_signed` binds the signature to the delegation.

TX1 also has a separate, zero-value output note addressed to the hotkey. That
output is not the signed note.

### Eligible and padding note slots

ZKP #1 always has `BUNDLE_NOTE_SLOTS` note slots. The wallet places the real
eligible notes first, in persisted bundle order, then fills the remaining
slots with the exact synthetic padding notes used by the proof.

For every padding slot, the wallet samples a fresh valid `rho` and a fresh
valid `rseed`, constructs a note for the delegating account, and computes its
extracted note commitment. The wallet persists these padding secrets because
the proof must reconstruct the same notes.

Let `cmx[0]` through `cmx[4]` be the canonical 32-byte encodings of the
extracted commitments in that exact slot order. Implementations MUST NOT sort
or otherwise reorder the commitments after padding.

### How `rho_signed` is chosen

`rho_signed` is not sampled and is not copied from an eligible or padding
note. It is deterministically derived as the seven-input Pallas Poseidon hash:

```text
rho_signed =
    Poseidon(cmx[0], cmx[1], cmx[2], cmx[3], cmx[4], VAN, round_id)
```

Each input is interpreted from its canonical 32-byte encoding as a Pallas base
field element. `VAN` is the already-computed commitment containing the one
hotkey address, delegated weight, round, and VAN blinding value. `round_id` is
the same voting-round field element used in the VAN and ZKP #1.

The same seven inputs always produce the same `rho_signed`. A fresh delegation
setup will normally produce a different value because the VAN blinding value
and any padding-note secrets are fresh.

### How the signed note is made

After deriving `rho_signed`, the wallet:

1. derives the recipient from the delegating account FVK at external
   diversifier index zero;
2. samples a fresh 32-byte `rseed_signed`, retrying until it is valid for
   `rho_signed`; and
3. constructs an Ironwood V3 note with:

   ```text
   recipient = account_fvk.address_at(0, External)
   value     = 1 zatoshi
   rho       = rho_signed
   rseed     = rseed_signed
   ```

The 1-zatoshi value makes the action non-zero for existing signer display
paths. It is synthetic and is not taken from the holder's balance.

The wallet uses Merkle position zero and 32 zero-valued sibling encodings for
the signed note's synthetic authentication path. Its anchor is computed from
that note and path only so that the normal Zcash builder accepts the spend.
The signed note is not in the Zcash note-commitment tree.

ZKP #1 MUST reconstruct the signed-note nullifier from the exact same note:
the delegating-account recipient, 1-zatoshi value, `rho_signed`,
`rseed_signed`, V3 note version, position zero, and account key material. TX1
places this nullifier in its spend, so it is covered by the ZIP-244 sighash.
This is what binds the signature to the eligible-note slots, VAN, hotkey, and
round.

```text
eligible notes --+
padding notes ----+--> cmx[0..4] --+
                                      |
one hotkey address --> VAN ------------+--> rho_signed
round ---------------------------------+        |
                                                v
signed note --> nf_signed --> TX1 sighash --> SpendAuth signature
     |
     +-- owned by the delegating account

one hotkey address --> zero-value output --> cmx_new
```

## Transaction construction

### Global fields

The wallet MUST construct the PCZT global fields as follows:

| Field | Value |
| --- | --- |
| Transaction version | `TxVersion::suggested_for_branch(branch_id)` |
| Consensus branch ID | Branch active at the voting snapshot height |
| Lock time | `0` |
| Expiry height | `0` |
| Transparent bundle | Absent |
| Sapling bundle | Absent |
| Orchard bundle | Absent |
| Ironwood bundle | Present, V3 |

The current library accepts only the NU6.3 branch, so the suggested
transaction version resolves to V6.

The zero expiry height is acceptable only because TX1 is never broadcast.

### Ironwood bundle

The wallet MUST use the Ironwood builder with the V3 bundle version, default
flags, and `BundleType::DEFAULT`.

The builder may pad and independently shuffle spends and outputs. The wallet
MUST retry construction until the real spend and real output occupy the same
action index. It MUST persist that action index with the signing request.

The real spend is:

| Field | Value |
| --- | --- |
| Note | The signed synthetic note |
| Merkle position | `0` |
| Authentication path | 32 zero-valued sibling encodings |
| Anchor | Root computed from the synthetic note and synthetic path |
| `alpha` | Fresh scalar sampled by the Ironwood builder |
| `rk` | Randomized verification key derived from `ak` and `alpha` |
| ZIP-32 path | `m / 32' / coin_type' / account'` |

The real output is:

| Field | Value |
| --- | --- |
| Recipient | Voting hotkey address |
| Value | `0` zatoshi |
| OVK | External outgoing viewing key of the delegating account |
| Memo | 512-byte delegation display memo |
| `rseed_output` | Fresh randomness sampled by the builder |

The implementation currently has a 1-zatoshi synthetic spend and a zero-value
output. This produces a nominal positive 1-zatoshi shielded value balance.
No real fee is paid because TX1 is never extracted or broadcast.

The zero-value output is protocol-relevant: ZKP #1 reconstructs `cmx_new` for
that same output value. Implementations MUST NOT change it to a 1-zatoshi
output without changing and versioning the proof statement.

### Memo

The current display memo is:

```text
I am authorizing this hotkey managed by my wallet to vote on {round_name}.
Amount: {whole}.{fraction:08} ZEC.
```

The memo is informational. It is covered by the transaction sighash, but the
vote-chain verifier does not parse it. Wallets SHOULD show the same round,
weight, and hotkey address in their own confirmation UI instead of relying
only on a hardware signer's interpretation of the PCZT.

### PCZT finalization

After the bundle is built, the wallet MUST:

1. add the hardened ZIP-32 derivation path to the real spend;
2. build the PCZT with the Creator role;
3. run the IO Finalizer role;
4. serialize the full PCZT;
5. compute `Signer::shielded_sighash()` from the finalized PCZT; and
6. persist the sighash, `rk`, `alpha`, action index, `nf_signed`,
   `cmx_new`, both rseeds, and proof inputs before requesting a signature.

The caller MUST retain the exact full PCZT for the active signing session.
The current voting database persists the binding fields, but not the full PCZT
bytes.

The sighash is the 32-byte ZIP-244 shielded signature digest. It is not a
custom voting hash.

## Signing

### Software wallet

Software signing MUST remain inside the wallet's seed boundary:

1. Verify that the selected seed's ZIP-32 fingerprint equals the persisted
   signing request fingerprint.
2. Derive the unified spending key for the request network and account index.
3. Derive the SpendAuthorizingKey `ask`.
4. Parse the persisted `alpha` as a canonical Pallas scalar.
5. Compute the randomized signing key `rsk = ask.randomize(alpha)`.
6. Produce a RedPallas SpendAuth signature over the exact persisted 32-byte
   sighash using fresh CSPRNG randomness.

Only the 64-byte signature should cross back out of the wallet signing
boundary.

### External signer

For a PCZT signer such as Keystone, the wallet MUST:

1. redact the full PCZT for the Signer role;
2. send only the redacted PCZT to the signer;
3. receive a structurally parseable signed PCZT;
4. extract the SpendAuth signature from the persisted action index; and
5. pair the signature with the original persisted sighash and `rk`.

The wallet MUST NOT accept an `rk`, sighash, action index, network, account
path, or delegation field supplied separately by the signer response.

## Verification and submission

Before assembling the vote-chain delegation submission, the wallet MUST:

1. require a 32-byte sighash and 64-byte signature;
2. require the supplied sighash to equal the write-once persisted TX1
   sighash;
3. verify the signature under the write-once persisted `rk` and sighash;
4. require ZKP #1 public values `rk`, `nf_signed`, `cmx_new`, VAN, and
   governance nullifiers to equal the values persisted during TX1 setup; and
5. verify the final delegation proof before releasing a submission whenever
   the wallet has a local verifier available.

The vote-chain submission contains the SpendAuth signature, `rk`, and TX1
sighash, but it is not TX1 and does not contain a Zcash transaction.

To hand the resulting voting authority to another application, use the
[external software export](exporting-to-external-software.md). Do not export
the wallet seed or account spending key.

Signing state is one-shot. After a restart, the wallet MAY resume only if it
retained the exact signing request, including the full PCZT. Otherwise it MUST
clear the unsigned setup and build a fresh one. It MUST NOT combine `alpha`,
`rk`, action fields, rseeds, a sighash, or a signature from different setup
attempts.

## Rust example

The caller first prepares a [`PreparedDelegationBundle`][prepared] using the
wallet and round state. TX1 construction itself is then:

```rust
use anyhow::{ensure, Context, Result};
use zcash_voting::prelude::{
    pczt_sighash, spend_auth_signature, NoopProgressReporter,
    PreparedDelegationBundle, PreparedSigner, VotingDb,
};

fn build_tx1(
    voting_db: &VotingDb,
    prepared: &PreparedDelegationBundle,
) -> Result<zcash_voting::delegate::KeystoneSigningRequest> {
    let progress = NoopProgressReporter;
    let request = prepared
        .keystone_request(voting_db, &progress)
        .context("build TX1 and persist its binding fields")?;

    let recomputed = pczt_sighash(&request.pczt_bytes)?;
    ensure!(
        recomputed.as_slice() == request.pczt_sighash.as_slice(),
        "TX1 sighash does not match its serialized PCZT"
    );
    ensure!(request.rk.len() == 32, "TX1 rk must be 32 bytes");

    // Display `request.display_memo`, the voting hotkey address, and bundle
    // weight in the wallet UI. Send only `redacted_pczt_bytes` to Keystone.
    Ok(request)
}

fn accept_signed_tx1(
    voting_db: &VotingDb,
    prepared: &PreparedDelegationBundle,
    request: &zcash_voting::delegate::KeystoneSigningRequest,
    signed_pczt_bytes: &[u8],
) -> Result<zcash_voting::delegate::DelegationSubmission> {
    let action_index =
        usize::try_from(request.action_index).context("invalid action index")?;
    let signature = spend_auth_signature(signed_pczt_bytes, action_index)
        .context("extract TX1 SpendAuth signature")?;
    let signer = PreparedSigner::signature_from_bytes(
        &signature,
        &request.pczt_sighash,
    )?;

    // `submission` checks the supplied sighash against persisted TX1 state
    // and verifies the signature under the persisted rk. ZKP #1 must have
    // been generated before this call.
    prepared
        .submission(voting_db, signer)
        .context("assemble vote-chain delegation submission")
}
```

The complete caller-oriented flows are implemented in
[`wallet-example/src/example_delegation.rs`][example]:

- `build_keystone_delegation_request` builds TX1 and returns the full and
  signer-redacted PCZTs;
- `prove_and_submit_keystone_delegation_bundle` extracts the returned
  SpendAuth signature and assembles the delegation submission; and
- `prove_and_submit_delegation_bundle` demonstrates the equivalent
  wallet-owned software signing path.

## Implementation references

- TX1 construction:
  [`zcash_voting/src/action.rs`](../zcash_voting/src/action.rs)
- Prepared signing API:
  [`zcash_voting/src/delegate.rs`](../zcash_voting/src/delegate.rs)
- Wallet integration example:
  [`wallet-example/src/example_delegation.rs`](../wallet-example/src/example_delegation.rs)
- ZIP-244:
  <https://zips.z.cash/zip-0244>

[prepared]: ../zcash_voting/src/delegate.rs
[example]: ../wallet-example/src/example_delegation.rs
