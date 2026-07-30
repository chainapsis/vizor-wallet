# Exporting to external software

## Purpose

After delegation, later votes are authorized by the voting hotkey instead of
the Zcash account spending key. A wallet can hand that delegated voting
authority to external software by sending an export package.

This export does not include the wallet seed, mnemonic, account spending key,
or full viewing key. It also does not move ZEC.

## Export contents

The package has three credential fields:

| Field | Contents |
| --- | --- |
| `hotkey_private_key` | The 64-byte opaque secret returned by `VotingHotkey::stored_secret()`. |
| `signature` | The TX1 SpendAuth signature record for each delegated bundle. |
| `ivk` | The delegating account's 64-byte raw external Orchard incoming viewing key. |

The package also needs a format version, Zcash network, and voting round ID so
that the receiver can interpret those fields in the correct context. These
are transport metadata, not additional authority.

### Hotkey private key

`hotkey_private_key` is the name used by the export format. In the current
Rust API its value is the opaque 64-byte
`VotingHotkey::stored_secret()` value. It is seed material for the
voting-only key hierarchy, not the Zcash wallet seed and not a directly
encoded 32-byte Orchard spending key.

The receiver reconstructs the hotkey using:

```rust
let hotkey =
    VotingHotkey::from_stored_secret(hotkey_private_key, network)?;
```

The current derivation uses voting-hotkey account index zero, external scope,
and address index zero. After reconstruction, the receiver SHOULD verify that
the resulting raw Orchard address equals the hotkey address used by the
delegation.

Possession of this field is sufficient to sign later votes for every exported
delegation that targets this hotkey. It does not grant authority over the
holder's Zcash account.

### Signature

The signature is the 64-byte RedPallas SpendAuth signature produced for TX1.
It is meaningful only with the exact 32-byte ZIP-244 sighash and 32-byte
randomized verification key `rk` under which it verifies. The logical
`signature` field therefore carries a record:

```text
signature:
    bundle_index
    spend_auth_sig
    sighash
    rk
```

The receiver MUST verify `spend_auth_sig` under `rk` and `sighash` before
accepting the package. It MUST also bind the record to the package's network,
round ID, and bundle index.

One TX1 authorizes one delegation bundle. If a voting identity has more than
five eligible notes, it has more than one TX1 and the export MUST contain one
signature record for every delegated bundle. All of those bundles SHOULD
target the one exported hotkey.

### IVK

`ivk` is the delegating account's external Orchard incoming viewing key:

```text
account_fvk.to_ivk(External).to_bytes()
```

Its encoding is 64 bytes: the 32-byte diversifier key followed by the
32-byte Orchard incoming-viewing-key field element. It is the IVK of the
account whose voting rights were delegated, not the hotkey's IVK. The
hotkey's viewing material can already be derived from
`hotkey_private_key`.

The IVK is read-only and cannot spend funds or create SpendAuth signatures.
It can, however, reveal addresses and incoming transaction data for the
delegating account, so the receiver MUST treat it as privacy-sensitive.

## Transfer and storage requirements

Exporting copies authority; it does not revoke the source wallet's copy. If
both applications retain the hotkey private key, both can attempt to vote with
the same delegated authority. The applications need an explicit ownership or
coordination policy to avoid conflicting actions.

The sender MUST use an authenticated, encrypted channel. Both sender and
receiver MUST keep `hotkey_private_key` out of logs, analytics, crash reports,
clipboard history, and unencrypted backups. The receiver MUST validate field
lengths, signature context, network, and round before storing the package, and
SHOULD place the hotkey private key in platform secure storage.

The receiver SHOULD zero temporary plaintext buffers after import. Deleting
the source copy after a successful import is a product decision, not a
protocol-level revocation mechanism.

## Relationship to TX1

TX1 delegates one eligible-note bundle to the hotkey; the export package hands
control of that hotkey to external software. See
[Delegation signing transaction (TX1)](delegation-signing-transaction.md) for
the note construction, `rho_signed` binding, and signature flow.
