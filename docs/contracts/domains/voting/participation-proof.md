# Voting participation proof and trust

Use when changing viewing-key inspection, vote-RPC queries, proof verification, trust pins, or unknown eligibility.

Implementation: [voting_participation_provider.dart](../../../../lib/src/providers/voting/voting_participation_provider.dart).

Home schedules a client-side check for active candidate rounds (including those whose Home card is hidden) after
wallet sync settles with the snapshot available. Detail entry also waits for the same deduplicated
check before preparing voting power. The list preview and submission/recovery
jobs do not start another participation check. Home keeps its card hidden until a positive actionable result is confirmed.
Previously confirmed visibility is retained while checks wait or fail. Settings remains a permanent entry point.

Rust reads the account's Orchard full viewing key and snapshot notes. It derives
real-note governance nullifiers with the pinned `zcash_voting` SDK. This works for
UFVK-only Keystone accounts without QR interaction, spending keys, hotkeys, PIR,
or proof generation. Actual voting still uses the existing signer flow.

The Dart client uses the wallet's network HTTP transport, including its Tor policy.
It reads `/commit`, `/validators`, then one `/abci_query` per previously unknown real note, four at a
time, at the signed header height minus one. Each request has a ten-second timeout;
a check has a four-minute budget and a 1,024-note cap. It does not query Lambda
with account identifiers. A vote RPC can observe and correlate the queried
governance identifiers; this is not private information retrieval. Do not log
query URLs, keys, evidence, or raw transport errors.

## Proof and trust boundary

The Cosmos vote store key is `01 00 || round_id || governance_nullifier`.
Rust verifies IAVL membership (value `01`) or non-membership, then the multistore
proof for `vote` against the signed header's app hash. It checks chain ID, height,
header hash, time (at most ten minutes old or one minute ahead), validator-set
hash and the Tendermint commit's signature quorum. Missing/pruned/invalid proofs
remain unknown. Valid sibling proofs are retained; unknown notes are not used to
prepare a new delegation. A partial result only changes visibility when its
proven unused subset already meets the voting threshold. Otherwise the prior
display decision is retained.
Without a previous decision, the card stays hidden.

This is a reader anchored to a bundled consensus committee, not a full rotating
light client. The bundled public keys and original voting powers live in
`rust/src/wallet/voting/trust/`. Their hashes must match the original pins below,
which were captured from the official RPCs on 2026-09-10:

| Network | Chain | RPC | Validator-set hash |
| --- | --- | --- | --- |
| main | zvote-1 | https://vote-rpc-primary.valargroup.org | 621A1E2C532170C3C0BC2E951D26C1CCA7A0EFB009AA15820D648D336C64F6BD |
| test | svote-1 | https://stage.vote-rpc-primary.valargroup.org | 6E81F631CB63A527AB5A659529BA8942C46CCF78BA87D1B3AD4CF8AE5BDC2E8B |

The initial trust anchor relies on that official HTTPS bootstrap. The current
validator set must hash to the signed header, but need not hash to the bundled
pin. The same commit must have strictly more than two-thirds signing power under
both the bundled original powers and the current powers. Public-key/address
consistency, duplicate validators/signers and voting-power bounds are checked.
New powers cannot inflate a signer's contribution under the bundled anchor.

This permits limited validator replacement and power changes without more RPCs.
It does not advance the trust anchor or implement a time-bounded rotating light
client. Cumulative changes that lose the bundled >2/3 quorum require a reviewed
anchor update. The original committee remains a long-lived trust assumption;
this does not provide automatic protection against compromise of its retired
keys. Custom sources remain unsupported. Regtest retains its explicit disposable
exact-set anchor. Failed checks preserve the last confirmed display decision.

- Viewing-key snapshot inspection supports UFVK-only hardware without signing or
  proofs. Used rights do not prove every proposal was voted on. Local recovery
  takes precedence over new delegation setup.

- Route requests through the configured network transport. Participation
  queries expose correlatable governance identifiers to the vote RPC. Never log
  query keys, URLs, evidence, or raw transport errors.

## Related changes

For persisted evidence and invalidation, read [participation cache](participation-cache.md).
