//! Real BTC redesign-lock derivation — the first genuinely on-chain piece of `RealExecutor` (P5): the
//! consensus single-script lock + its P2WSH scriptPubKey, the artifact the solver must fund for every
//! BTC-leg swap.
//!
//! IDEALLY this reuses `btc-batcher`'s audited `tx::scripts::build_redesign_lock_script` + `p2wsh_spk`
//! verbatim (the spec's "reuse, don't reinvent crypto" tenet). A full path-dep is blocked by a hard
//! `links = "sqlite3"` conflict (btc-batcher's rusqlite-0.37 daemon tree vs orderbook-v2's rusqlite-0.31)
//! in the shared v3 workspace — the clean fix is to extract `btc-batcher/src/tx/scripts` into a leaf crate
//! both depend on, a ROOT-crate refactor outside v3's isolation scope (tracked in BUILD-LOG). Until then
//! the script is ported here and **PINNED byte-for-byte to btc-batcher's consensus golden vector**
//! (`redesign_lock_script_golden_vector`, itself the Rust↔TS parity anchor to
//! `packages/bitcoin/src/scripts.ts`). The golden test below fails on any single-byte drift.
//!
//! This module is daemon-free + chain-free (pure script derivation). The actual funding tx (UTXO select / sign /
//! broadcast / RBF) is done IN-PROCESS by the solver's `live_executor::fund_lock` (a dynamic-fee `BtcRpc` call) —
//! NOT via a btc-batcherd daemon (its full crate conflicts on the `rusqlite` `links` key); only the lock-script
//! crypto is ported here, byte-pinned to btc-batcher's consensus golden vector.

use sha2::{Digest, Sha256};

/// The material the redesign single-script lock binds (b2z-script-redesign-spec / 07 §2). `b_b` is the
/// SOLVER's BTC claim pubkey (from its own key pool — never the OB's to supply); `br_a` the initiator's
/// refund pubkey (counterparty material relayed by the OB). The three hashes are SHA256 commitments;
/// `t1 < t2` the CSV timelocks (Alice refund / solver force-claim).
pub struct LockMaterial {
    pub swap_hash: [u8; 32],
    pub h_a: [u8; 32],
    pub h_b: [u8; 32],
    pub b_b: [u8; 33],
    pub br_a: [u8; 33],
    pub t1: u32,
    pub t2: u32,
}

/// The derived lock leg: the consensus witnessScript + its P2WSH scriptPubKey (`OP_0 <sha256(script)>`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DerivedLock {
    pub witness_script_hex: String,
    pub p2wsh_spk_hex: String,
}

/// Minimal CScriptNum push (byte-identical to btc-batcher `push_scriptnum`): little-endian magnitude with
/// a sign-padding 0x00 when the top bit is set, length-prefixed.
fn push_scriptnum(out: &mut Vec<u8>, n: u32) {
    if n == 0 {
        out.push(0x00);
        return;
    }
    let mut bytes = Vec::new();
    let mut v = n;
    while v > 0 {
        bytes.push((v & 0xff) as u8);
        v >>= 8;
    }
    if bytes.last().copied().unwrap_or(0) & 0x80 != 0 {
        bytes.push(0x00);
    }
    out.push(bytes.len() as u8);
    out.extend_from_slice(&bytes);
}

/// Build the redesign single self-revealing P2WSH lock witnessScript (ported from
/// `btc-batcher::tx::scripts::build_redesign_lock_script`; pinned to its golden vector).
fn build_redesign_lock_script(m: &LockMaterial) -> Result<Vec<u8>, String> {
    if m.t1 >= m.t2 {
        return Err(format!("redesign lock requires t1 < t2 (got t1={}, t2={})", m.t1, m.t2));
    }
    // MINIMALDATA standardness (review fix #9): `push_scriptnum` byte-pushes the CSV operand, which is
    // mempool-NON-STANDARD for t ≤ 16 (those require OP_1..OP_16). A lock with a tiny CSV would build fine
    // but its refund/force-claim branch would be mempool-rejected → funds strand. Production t1/t2 are
    // 24/72/48/144 (all > 16); reject a misconfigured tiny CSV at the door.
    if m.t1 <= 16 || m.t2 <= 16 {
        return Err(format!("redesign lock requires t1,t2 > 16 for MINIMALDATA standardness (got t1={}, t2={})", m.t1, m.t2));
    }
    let mut s = Vec::with_capacity(220);
    // Branch 1: solver happy-path claim
    s.push(0x63); // OP_IF
    s.push(0xa8); // OP_SHA256
    s.push(0x20);
    s.extend_from_slice(&m.swap_hash);
    s.push(0x88); // OP_EQUALVERIFY
    s.push(0xa8); // OP_SHA256
    s.push(0x20);
    s.extend_from_slice(&m.h_b);
    s.push(0x88); // OP_EQUALVERIFY
    s.push(0x21);
    s.extend_from_slice(&m.b_b);
    s.push(0xac); // OP_CHECKSIG
    s.push(0x67); // OP_ELSE
                  // Branch 2: Alice unilateral refund (t ≥ t1)
    s.push(0x63); // OP_IF (inner)
    push_scriptnum(&mut s, m.t1);
    s.push(0xb2); // OP_CSV
    s.push(0x75); // OP_DROP
    s.push(0xa8); // OP_SHA256
    s.push(0x20);
    s.extend_from_slice(&m.h_a);
    s.push(0x88); // OP_EQUALVERIFY
    s.push(0x21);
    s.extend_from_slice(&m.br_a);
    s.push(0xac); // OP_CHECKSIG
    s.push(0x67); // OP_ELSE (inner)
                  // Branch 3: solver force-claim (t ≥ t2)
    push_scriptnum(&mut s, m.t2);
    s.push(0xb2); // OP_CSV
    s.push(0x75); // OP_DROP
    s.push(0xa8); // OP_SHA256
    s.push(0x20);
    s.extend_from_slice(&m.h_b);
    s.push(0x88); // OP_EQUALVERIFY
    s.push(0x21);
    s.extend_from_slice(&m.b_b);
    s.push(0xac); // OP_CHECKSIG
    s.push(0x68); // OP_ENDIF (inner)
    s.push(0x68); // OP_ENDIF (outer)
    Ok(s)
}

/// P2WSH scriptPubKey = `OP_0 <32-byte SHA256(witnessScript)>` (btc-batcher `p2wsh_spk`).
fn p2wsh_spk(script: &[u8]) -> Vec<u8> {
    let h = Sha256::digest(script);
    let mut spk = Vec::with_capacity(34);
    spk.push(0x00);
    spk.push(0x20);
    spk.extend_from_slice(&h);
    spk
}

/// Derive the redesign P2WSH lock from material (validates `b_b`/`br_a` are 33-byte compressed pubkeys +
/// `t1 < t2`). The fundable bech32 address is `OP_0 <sha256(script)>` rendered for the target network — a
/// presentation step owned by the funding daemon (`btc-batcherd`), which converts this spk before paying.
pub fn derive_lock(m: &LockMaterial) -> Result<DerivedLock, String> {
    if m.b_b[0] != 0x02 && m.b_b[0] != 0x03 {
        return Err("b_b must be a 33-byte compressed secp256k1 pubkey (prefix 02/03)".into());
    }
    if m.br_a[0] != 0x02 && m.br_a[0] != 0x03 {
        return Err("br_a must be a 33-byte compressed secp256k1 pubkey (prefix 02/03)".into());
    }
    let script = build_redesign_lock_script(m)?;
    let spk = p2wsh_spk(&script);
    Ok(DerivedLock { witness_script_hex: hex::encode(&script), p2wsh_spk_hex: hex::encode(&spk) })
}

/// Which redesign branch a spend takes (selects the witness shape + the CSV/nSequence the spend needs).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SpendBranch {
    /// Branch 1 — solver happy-path claim (no CSV): `[sig_B, k_B, swap_secret, 0x01, script]`.
    Claim,
    /// Branch 2 — initiator unilateral refund (nSequence ≥ t1): `[sig_A, k_A, 0x01, ∅, script]`.
    Refund,
    /// Branch 3 — solver force-claim after refund (nSequence ≥ t2): `[sig_B, k_B, ∅, ∅, script]`.
    ForceClaim,
}

/// Branch-1 claim witness (ported from `btc-batcher::tx::scripts::redesign_claim_witness`, golden-pinned).
/// `sig_b_der` is raw DER (no sighash byte — appended here, mirroring the audited impl).
pub fn claim_witness(sig_b_der: &[u8], k_b: &[u8; 32], swap_secret: &[u8; 32], sighash_type: u8, witness_script: &[u8]) -> Vec<Vec<u8>> {
    let mut sig = sig_b_der.to_vec();
    sig.push(sighash_type);
    vec![sig, k_b.to_vec(), swap_secret.to_vec(), vec![0x01], witness_script.to_vec()]
}

/// Branch-2 refund witness (ported from `redesign_refund_witness`, golden-pinned). Inner selector TRUE,
/// outer selector empty. The spending input's `nSequence` must encode ≥ t1.
pub fn refund_witness(sig_a_der: &[u8], k_a: &[u8; 32], sighash_type: u8, witness_script: &[u8]) -> Vec<Vec<u8>> {
    let mut sig = sig_a_der.to_vec();
    sig.push(sighash_type);
    vec![sig, k_a.to_vec(), vec![0x01], vec![], witness_script.to_vec()]
}

/// Branch-3 force-claim witness (ported from `redesign_force_claim_witness`, golden-pinned). Both selectors
/// empty (ELSE/ELSE). The spending input's `nSequence` must encode ≥ t2.
pub fn force_claim_witness(sig_b_der: &[u8], k_b: &[u8; 32], sighash_type: u8, witness_script: &[u8]) -> Vec<Vec<u8>> {
    let mut sig = sig_b_der.to_vec();
    sig.push(sighash_type);
    vec![sig, k_b.to_vec(), vec![], vec![], witness_script.to_vec()]
}

/// Hex-encode a witness stack (for the daemon enqueue / a `ClientFrame::SignedTx`-style relay).
pub fn witness_hex(items: &[Vec<u8>]) -> Vec<String> {
    items.iter().map(hex::encode).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The consensus golden vector — IDENTICAL inputs to btc-batcher's `redesign_lock_script_golden_vector`
    /// (and `packages/bitcoin/src/scripts.ts`). Proves the port produces the EXACT consensus bytes; a
    /// single off-by-one would change the lock address and break every BTC-leg swap.
    fn golden() -> LockMaterial {
        let mut b_b = [0u8; 33];
        b_b[0] = 0x03;
        b_b[1..].fill(0xbb);
        let mut br_a = [0u8; 33];
        br_a[0] = 0x02;
        br_a[1..].fill(0xaa);
        LockMaterial { swap_hash: [0x11u8; 32], h_a: [0x33u8; 32], h_b: [0x22u8; 32], b_b, br_a, t1: 72, t2: 144 }
    }

    #[test]
    fn derive_lock_matches_consensus_golden_vector() {
        let d = derive_lock(&golden()).expect("derive");
        let expected_script = concat!(
            "63a820", "1111111111111111111111111111111111111111111111111111111111111111", "88",
            "a820", "2222222222222222222222222222222222222222222222222222222222222222", "88",
            "2103", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "ac",
            "67",
            "63", "0148", "b275",
            "a820", "3333333333333333333333333333333333333333333333333333333333333333", "88",
            "2102", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "ac",
            "67",
            "029000", "b275",
            "a820", "2222222222222222222222222222222222222222222222222222222222222222", "88",
            "2103", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "ac",
            "68", "68",
        );
        assert_eq!(d.witness_script_hex, expected_script, "witnessScript must match consensus golden bytes");
        // P2WSH spk = OP_0 <32-byte sha256(script)> → 34 bytes, prefix 0020.
        assert!(d.p2wsh_spk_hex.starts_with("0020"));
        assert_eq!(d.p2wsh_spk_hex.len(), 68, "34-byte P2WSH scriptPubKey");
    }

    #[test]
    fn rejects_t1_ge_t2() {
        let mut m = golden();
        m.t1 = 144;
        m.t2 = 72;
        assert!(derive_lock(&m).is_err());
    }

    #[test]
    fn rejects_tiny_csv_minimaldata() {
        // review fix #9: t ≤ 16 → non-minimal CSV push → mempool-non-standard → rejected at build time.
        let mut m = golden();
        m.t1 = 10;
        m.t2 = 20;
        assert!(derive_lock(&m).is_err(), "t1<=16 must be rejected");
        let mut m2 = golden();
        m2.t1 = 17;
        m2.t2 = 16; // t2<=16 (and t1>=t2) → rejected
        assert!(derive_lock(&m2).is_err());
        // boundary: 17/18 both > 16 → ok
        let mut ok = golden();
        ok.t1 = 17;
        ok.t2 = 18;
        assert!(derive_lock(&ok).is_ok(), "t>16 is allowed");
    }

    #[test]
    fn rejects_malformed_pubkey() {
        let mut m = golden();
        m.b_b[0] = 0x00; // not a valid compressed-pubkey prefix
        assert!(derive_lock(&m).is_err());
    }

    /// Branch-1/2/3 witness item counts + selectors — IDENTICAL assertions to btc-batcher's
    /// `redesign_witness_item_counts_and_selectors`. A wrong selector byte spends the wrong branch (a
    /// fund-safety bug); the golden pin guarantees the port matches the audited consensus shapes.
    #[test]
    fn witness_shapes_match_consensus_golden() {
        let script = vec![0xabu8; 10];
        let sig_der = vec![0x30u8, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01];
        let k = [0x42u8; 32];
        let secret = [0x55u8; 32];
        let sh = 0x01u8;

        // Branch 1 — claim: [sig+sighash, k_B, secret, 0x01, script]
        let claim = claim_witness(&sig_der, &k, &secret, sh, &script);
        assert_eq!(claim.len(), 5);
        assert_eq!(claim[0].last().copied(), Some(sh), "claim sig ends with sighash byte");
        assert_eq!(claim[1], k.to_vec());
        assert_eq!(claim[2], secret.to_vec());
        assert_eq!(claim[3], vec![0x01], "claim outer selector = [0x01]");
        assert_eq!(claim[4], script);

        // Branch 2 — refund: [sig+sighash, k_A, 0x01, ∅, script]
        let refund = refund_witness(&sig_der, &k, sh, &script);
        assert_eq!(refund.len(), 5);
        assert_eq!(refund[0].last().copied(), Some(sh));
        assert_eq!(refund[2], vec![0x01], "refund inner selector = [0x01]");
        assert!(refund[3].is_empty(), "refund outer selector empty (FALSE)");
        assert_eq!(refund[4], script);

        // Branch 3 — force-claim: [sig+sighash, k_B, ∅, ∅, script]
        let force = force_claim_witness(&sig_der, &k, sh, &script);
        assert_eq!(force.len(), 5);
        assert_eq!(force[0].last().copied(), Some(sh));
        assert!(force[2].is_empty(), "force inner selector empty");
        assert!(force[3].is_empty(), "force outer selector empty");
        assert_eq!(force[4], script);

        // hex helper round-trips the stack
        let h = witness_hex(&claim);
        assert_eq!(h.len(), 5);
        assert_eq!(h[3], "01");
    }
}
