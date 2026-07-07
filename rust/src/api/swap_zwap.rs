//! FRB surface for the zwap BTC↔ZEC atomic-swap client.
//!
//! Keeps to the project's FRB rule: primitives / `String` / flat structs only.
//! All Zcash/Bitcoin/Pallas type manipulation lives in [`crate::zwap`]; this
//! layer just decodes hex, calls in, and re-encodes hex.
//!
//! Current surface is the pure, offline b2z (BTC→ZEC) material derivation —
//! the two addresses a swap presents. The async orchestrator (orderbook /
//! indexer drive) lands in a later phase.

use crate::zwap::b2z::{derive_b2z_material, LockTimelocks, SolverPublicHalf};

/// Flat, FRB-friendly result of [`zwap_derive_b2z_material`].
pub struct ZwapB2zMaterial {
    /// Bech32 P2WSH address the user funds with BTC (their lock deposit).
    pub btc_lock_address: String,
    /// Lock witnessScript (hex) — retained for the later spend/refund path.
    pub witness_script_hex: String,
    /// Joint Orchard unified address the solver funds and the user sweeps.
    pub joint_zec_address: String,
    /// Joint Orchard UFVK (`uview…`) — view-only key to scan the joint UA.
    pub joint_zec_ufvk: String,
    /// Joint Orchard `nk`/`rivk` (32-byte hex) — required (with the reconstructed
    /// `ask`) to build the joint-note sweep. These are the raw values, NOT the
    /// UFVK string.
    pub joint_zec_nk_hex: String,
    pub joint_zec_rivk_hex: String,
    /// Joint `ak`/`ivk`/`diversifier` (hex) — to trial-decrypt the note locally.
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    /// `swap_hash = SHA256(secret)`, hex (lock branch-1 commitment).
    pub swap_hash_hex: String,
    /// `h_a = SHA256(k_a)`, hex (lock refund-branch commitment).
    pub h_a_hex: String,
}

fn hex32(s: &str, what: &str) -> Result<[u8; 32], String> {
    let v = hex::decode(s).map_err(|e| format!("{what}: bad hex: {e}"))?;
    v.try_into().map_err(|_| format!("{what}: expected 32 bytes"))
}

fn hex33(s: &str, what: &str) -> Result<[u8; 33], String> {
    let v = hex::decode(s).map_err(|e| format!("{what}: bad hex: {e}"))?;
    v.try_into().map_err(|_| format!("{what}: expected 33 bytes"))
}

/// Derive the displayable b2z (BTC→ZEC) material for `swap_id` from the wallet
/// `seed` (hex) and the solver's verified public Phase0 half.
///
/// `solver_ak_sec1` (66 hex chars / 33 bytes), `solver_nsk_le` (64/32),
/// `solver_b_b` (66/33), `solver_h_b` (64/32) come from a poold entry the
/// caller has already re-verified. `network` is `mainnet` | `testnet` |
/// `regtest`. Pure and offline; no chain or network I/O.
#[allow(clippy::too_many_arguments)]
pub fn zwap_derive_b2z_material(
    seed_hex: String,
    swap_id: String,
    solver_ak_sec1: String,
    solver_nsk_le: String,
    solver_b_b: String,
    solver_h_b: String,
    t1: u32,
    t2: u32,
    network: String,
) -> Result<ZwapB2zMaterial, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let solver = SolverPublicHalf {
        ak_sec1: hex33(&solver_ak_sec1, "solver_ak_sec1")?,
        nsk_le: hex32(&solver_nsk_le, "solver_nsk_le")?,
        b_b: hex33(&solver_b_b, "solver_b_b")?,
        h_b: hex32(&solver_h_b, "solver_h_b")?,
    };
    let m = derive_b2z_material(&seed, &swap_id, &solver, LockTimelocks { t1, t2}, &network)?;
    Ok(ZwapB2zMaterial {
        btc_lock_address: m.btc_lock_address,
        witness_script_hex: m.witness_script_hex,
        joint_zec_address: m.joint_zec_address,
        joint_zec_ufvk: m.joint_zec_ufvk,
        joint_zec_nk_hex: m.joint_zec_nk_hex,
        joint_zec_rivk_hex: m.joint_zec_rivk_hex,
        joint_zec_ak_hex: m.joint_zec_ak_hex,
        joint_zec_ivk_hex: m.joint_zec_ivk_hex,
        joint_zec_diversifier_hex: m.joint_zec_diversifier_hex,
        swap_hash_hex: m.swap_hash_hex,
        h_a_hex: m.h_a_hex,
    })
}

/// The wallet's own public Orchard half + hashlock commitment for `swap_id` —
/// what the wallet reports to the orderbook at Phase0 so the solver can derive
/// and verify the same joint UA. Hex-encoded.
pub struct ZwapInitiatorHalf {
    pub ak_sec1: String,
    pub nsk_le: String,
    /// `h_a = SHA256(k_a)` — published; `k_a` itself stays in the wallet.
    pub h_a_hex: String,
    /// `swap_hash = SHA256(secret)` — the lock's branch-1 commitment.
    pub swap_hash_hex: String,
}

/// Derive the wallet's public Phase0 contribution for `swap_id`. The private
/// scalar `k_a` and `secret` are NOT returned — only their commitments and the
/// public Orchard half.
pub fn zwap_derive_initiator_half(
    seed_hex: String,
    swap_id: String,
) -> Result<ZwapInitiatorHalf, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let secret = crate::zwap::dkm::derive_swap_secret(&seed, &swap_id);
    Ok(ZwapInitiatorHalf {
        ak_sec1: hex::encode(half.ak_sec1),
        nsk_le: hex::encode(half.nsk_le),
        h_a_hex: hex::encode(crate::zwap::dkm::hashlock_commit(&half.k_be)),
        swap_hash_hex: hex::encode(crate::zwap::dkm::hashlock_commit(&secret)),
    })
}

// ---------------------------------------------------------------------------
// Settlement-side crypto primitives. The Dart orchestrator (which drives the
// orderbook/indexer/poold HTTP flow, mirroring the SDK's `runB2z`) calls these
// for the fund-critical Orchard work. JSON in/out matches the `orchard-wasm`
// request/response shapes the SDK already uses, so the Dart side can reuse the
// same payloads. Private keys never cross the FFI boundary as bare scalars —
// `ask` is reconstructed here from the two revealed BE scalars.
// ---------------------------------------------------------------------------

/// Reveal the wallet's per-swap swap secret for `swap_id` (the `SecretReveal`
/// step). Only call when the orderbook FSM says the wallet owns the reveal.
pub fn zwap_reveal_secret_hex(seed_hex: String, swap_id: String) -> Result<String, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    Ok(hex::encode(crate::zwap::dkm::derive_swap_secret(&seed, &swap_id)))
}

/// The wallet's own spend-auth scalar `k_a` (BE hex) for `swap_id` — needed to
/// reconstruct the joint `ask` once the counterparty reveals `k_b` on-chain.
pub fn zwap_k_user_be_hex(seed_hex: String, swap_id: String) -> Result<String, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    Ok(hex::encode(half.k_be))
}

/// Reconstruct the joint Orchard spend-auth scalar `ask = (k_a + k_b) mod q`
/// (LE hex, the form `orchard_spend` consumes) from the two BE scalars. `k_a`
/// is the wallet's own; `k_b` is the solver's, revealed in its on-chain claim.
pub fn zwap_joint_ask_le_hex(k_a_be_hex: String, k_b_be_hex: String) -> Result<String, String> {
    let k_a = hex32(&k_a_be_hex, "k_a_be")?;
    let k_b = hex32(&k_b_be_hex, "k_b_be")?;
    let ask_be = crate::zwap::joint_keys::derive_joint_ask_secret(&k_a, &k_b)?;
    let mut ask_le = ask_be;
    ask_le.reverse();
    Ok(hex::encode(ask_le))
}

/// Trial-decrypt the joint note from compact blocks. `request_json` is the
/// `orchard-wasm` DecryptRequest (ivk, diversifier, blocks, frontier_hex, …);
/// returns the DecryptResponse JSON (found notes + tree_size).
pub fn zwap_orchard_trial_decrypt(request_json: String) -> Result<String, String> {
    crate::zwap::orchard_claim::orchard_trial_decrypt(&request_json)
}

/// Build + prove + sign + serialize the joint-note sweep. `request_json` is the
/// `orchard-wasm` SpendRequest (ask, nk, rivk, note, merkle_path, dest, …);
/// returns the SpendResponse JSON (raw_tx_hex + txid) ready to broadcast.
pub fn zwap_orchard_spend(request_json: String) -> Result<String, String> {
    crate::zwap::orchard_claim::orchard_spend(&request_json)
}

/// Derive the joint Orchard unified address + ivk/diversifier from the combined
/// `ak`/`nk`/`rivk` (hex). `request_json` is the `orchard-wasm` DeriveRequest.
pub fn zwap_orchard_derive(request_json: String) -> Result<String, String> {
    crate::zwap::orchard_claim::orchard_derive(&request_json)
}

// ---------------------------------------------------------------------------
// e2z (ETH→ZEC) proxy — deposit-based EVM leg. The wallet shows the CREATE2
// deposit address (derived locally, fund-safe) + the joint ZEC UA; the user
// funds the deposit from their own ETH wallet (partial top-ups allowed).
// ---------------------------------------------------------------------------

/// Flat FRB result of [`zwap_derive_e2z_proxy_material`].
pub struct ZwapE2zMaterial {
    /// CREATE2 proxy deposit address (0x-hex) the user funds with ETH.
    pub deposit_address: String,
    /// The proxy CREATE2 salt (0x-hex).
    pub salt_hex: String,
    pub claim_buy_digest: String,
    pub refund_to_initiator_digest: String,
    pub refund_after_claim_digest: String,
    /// Joint Orchard unified address the user sweeps.
    pub joint_zec_address: String,
    pub joint_zec_ufvk: String,
    /// Joint Orchard `nk`/`rivk` (32-byte hex) for the sweep.
    pub joint_zec_nk_hex: String,
    pub joint_zec_rivk_hex: String,
    /// Joint `ak`/`ivk`/`diversifier` (hex) — for local trial-decryption.
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    pub swap_hash_hex: String,
    /// Canonical `proxyTerms` JSON to post to the orderbook at Phase0.
    pub proxy_terms_json: String,
}

fn hex20(s: &str, what: &str) -> Result<[u8; 20], String> {
    let v = hex::decode(s.trim_start_matches("0x")).map_err(|e| format!("{what}: bad hex: {e}"))?;
    v.try_into().map_err(|_| format!("{what}: expected 20 bytes"))
}

/// Derive the displayable e2z proxy material for `swap_id` from the wallet
/// `seed` (hex), the solver's verified relayed half, and the proxy escrow terms.
/// `initiator_evm_addr` is the user's own ETH wallet (the refund destination).
/// `token_addr` is the zero address for native ETH. Pure/offline.
#[allow(clippy::too_many_arguments)]
pub fn zwap_derive_e2z_proxy_material(
    seed_hex: String,
    swap_id: String,
    solver_ak_sec1: String,
    solver_nsk_le: String,
    solver_lock_pubkey: String,
    solver_refund_pubkey: String,
    solver_h_b: String,
    solver_evm_addr: String,
    amount_wei: String,
    token_addr: String,
    t0_abs: String,
    t1_abs: String,
    chain_id: u64,
    factory_addr: String,
    implementation_addr: String,
    initiator_evm_addr: String,
    network: String,
) -> Result<ZwapE2zMaterial, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let solver = crate::zwap::e2z::E2zSolverHalf {
        ak_sec1: hex33(&solver_ak_sec1, "solver_ak_sec1")?,
        nsk_le: hex32(&solver_nsk_le, "solver_nsk_le")?,
        lock_pubkey: hex33(&solver_lock_pubkey, "solver_lock_pubkey")?,
        refund_pubkey: hex33(&solver_refund_pubkey, "solver_refund_pubkey")?,
        h_b: hex32(&solver_h_b, "solver_h_b")?,
        solver_evm_addr: hex20(&solver_evm_addr, "solver_evm_addr")?,
    };
    let proxy = crate::zwap::e2z::E2zProxyTerms {
        amount: amount_wei.parse::<u128>().map_err(|e| format!("amount: {e}"))?,
        token: hex20(&token_addr, "token_addr")?,
        t0_abs: t0_abs.parse::<u128>().map_err(|e| format!("t0_abs: {e}"))?,
        t1_abs: t1_abs.parse::<u128>().map_err(|e| format!("t1_abs: {e}"))?,
        chain_id: chain_id as u128,
        factory: hex20(&factory_addr, "factory_addr")?,
        implementation: hex20(&implementation_addr, "implementation_addr")?,
    };
    let m = crate::zwap::e2z::derive_e2z_proxy_material(
        &seed,
        &swap_id,
        &solver,
        &proxy,
        hex20(&initiator_evm_addr, "initiator_evm_addr")?,
        &network,
    )?;
    Ok(ZwapE2zMaterial {
        deposit_address: m.deposit_address,
        salt_hex: m.salt_hex,
        claim_buy_digest: m.claim_buy_digest,
        refund_to_initiator_digest: m.refund_to_initiator_digest,
        refund_after_claim_digest: m.refund_after_claim_digest,
        joint_zec_address: m.joint_zec_address,
        joint_zec_ufvk: m.joint_zec_ufvk,
        joint_zec_nk_hex: m.joint_zec_nk_hex,
        joint_zec_rivk_hex: m.joint_zec_rivk_hex,
        joint_zec_ak_hex: m.joint_zec_ak_hex,
        joint_zec_ivk_hex: m.joint_zec_ivk_hex,
        joint_zec_diversifier_hex: m.joint_zec_diversifier_hex,
        swap_hash_hex: m.swap_hash_hex,
        proxy_terms_json: m.proxy_terms_json,
    })
}

// ---------------------------------------------------------------------------
// Orderbook identity / auth. The wallet's 32-byte seed IS the ed25519 secret
// key — the orderbook identity for that seed (matches the SDK `wallet.ts`
// `ed25519PubHexFromSeed` / `signChallengeWithSeed`). The seed never leaves
// Rust; Dart sends only the public key + the challenge signature.
// ---------------------------------------------------------------------------

fn ed25519_signing_key(seed_hex: &str) -> Result<ed25519_dalek::SigningKey, String> {
    let seed = hex32(seed_hex, "seed")?;
    Ok(ed25519_dalek::SigningKey::from_bytes(&seed))
}

/// The ed25519 public key (hex) for the wallet seed — the orderbook identity.
pub fn zwap_ob_identity_pubkey_hex(seed_hex: String) -> Result<String, String> {
    let sk = ed25519_signing_key(&seed_hex)?;
    Ok(hex::encode(sk.verifying_key().to_bytes()))
}

/// Sign an orderbook auth `challenge` (UTF-8 bytes) with the seed's ed25519 key.
/// Returns the 64-byte signature as hex.
pub fn zwap_ob_sign_challenge_hex(seed_hex: String, challenge: String) -> Result<String, String> {
    use ed25519_dalek::Signer;
    let sk = ed25519_signing_key(&seed_hex)?;
    Ok(hex::encode(sk.sign(challenge.as_bytes()).to_bytes()))
}

/// The b2z order `feMaterial` fields the wallet owns, matching the SDK
/// `buildFeMaterialAsync` exactly — everything except the hashbind proof, which
/// the caller produces by feeding [`Self::k_be_hex`] to the ProveKit prover.
///
/// `k_be_hex` is the raw spend-auth scalar `k_a` (BE) — the prover's input. It
/// is the one secret that must reach the prover. Production builds prove
/// on-device (native/hashbind_prover via `zwap_hashbind_native.dart`) so it
/// never leaves the process; debug builds may opt into the regtest HTTP
/// prover (`ZWAP_HASHBIND_PROVER_URL`), trading that for test convenience.
pub struct ZwapB2zOrderInputs {
    pub h_a: String,
    pub swap_hash: String,
    pub ak_a: String,
    pub nsk_a: String,
    pub lock_pubkey: String,
    pub refund_pubkey: String,
    pub k_be_hex: String,
}

/// Find a "safe" derive-id for `(seed, base_id)` whose derived spend-auth
/// scalar `k_a < 2^251` — the bound the DLEq/hashbind circuits prove over
/// (matches the SDK `findDleqSafeDeriveId`). Returns `base_id`, else
/// `base_id~1`, `base_id~2`, … (up to 256 tries). A raw `k_a` reduced mod the
/// ~254-bit Pallas order exceeds 2^251 often enough that order creation MUST
/// use a safe id or the prover/matcher rejects it.
pub fn zwap_find_safe_swap_id(seed_hex: String, base_id: String) -> Result<String, String> {
    use num_bigint::BigUint;
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let bound = BigUint::from(1u8) << 251u32;
    let is_safe = |id: &str| -> Result<bool, String> {
        let half = crate::zwap::dkm::derive_initiator_half(&seed, id)?;
        Ok(BigUint::from_bytes_be(&half.k_be) < bound)
    };
    if is_safe(&base_id)? {
        return Ok(base_id);
    }
    for i in 1..=256u32 {
        let cand = format!("{base_id}~{i}");
        if is_safe(&cand)? {
            return Ok(cand);
        }
    }
    Err(format!("no DLEq-safe derive-id within 256 tries of '{base_id}'"))
}

/// Assemble the b2z `feMaterial` inputs for `swap_id` (all hex). The returned
/// fields go verbatim into the order's `feMaterial` (plus `proofKind:"hashbind"`
/// and the `hashbindProof` the caller computes from `k_be_hex`).
pub fn zwap_b2z_order_inputs(
    seed_hex: String,
    swap_id: String,
) -> Result<ZwapB2zOrderInputs, String> {
    use secp256k1::{PublicKey, Secp256k1, SecretKey};
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let secret = crate::zwap::dkm::derive_swap_secret(&seed, &swap_id);
    let secp = Secp256k1::new();

    // lock_pubkey = k_a · secp_G (k_a is reduced < 2^255 < secp n, so valid).
    let k_sk = SecretKey::from_slice(&half.k_be).map_err(|e| format!("k_a as secp scalar: {e}"))?;
    let lock_pubkey = PublicKey::from_secret_key(&secp, &k_sk).serialize();

    // refund_pubkey = secp pub of SHA256(seed ‖ 0x42), the SDK deriveBtcRefundPubkey.
    let refund = {
        use sha2::{Digest, Sha256};
        let mut h = Sha256::new();
        h.update(&seed);
        h.update([0x42]);
        let sk = SecretKey::from_slice(&h.finalize()).map_err(|e| format!("refund sk: {e}"))?;
        PublicKey::from_secret_key(&secp, &sk).serialize()
    };

    Ok(ZwapB2zOrderInputs {
        h_a: hex::encode(crate::zwap::dkm::hashlock_commit(&half.k_be)),
        swap_hash: hex::encode(crate::zwap::dkm::hashlock_commit(&secret)),
        ak_a: hex::encode(half.ak_sec1),
        nsk_a: hex::encode(half.nsk_le),
        lock_pubkey: hex::encode(lock_pubkey),
        refund_pubkey: hex::encode(refund),
        k_be_hex: hex::encode(half.k_be),
    })
}

// ---------------------------------------------------------------------------
// z2b (ZEC→BTC) — the give-ZEC direction. The user funds the joint ZEC note and
// CLAIMS the solver-funded BTC lock (branch-1). Mirrors the b2z surface above
// with the role-flip baked into `crate::zwap::z2b`.
// ---------------------------------------------------------------------------

/// The z2b order `feMaterial` fields the wallet owns. Same shape as the b2z
/// inputs EXCEPT: z2b has NO `swap_hash` (the solver owns the secret), and the
/// FE-material `refundPubkey` field carries the user's per-swap BTC CLAIM pubkey
/// (`b_b`), not a refund key. `k_be_hex` is the hashbind prover input.
pub struct ZwapZ2bOrderInputs {
    pub h_a: String,
    pub ak_a: String,
    pub nsk_a: String,
    pub lock_pubkey: String,
    /// The user's per-swap BTC claim pubkey `b_b` — posted as `refundPubkey`.
    pub claim_pubkey: String,
    pub k_be_hex: String,
}

/// Assemble the z2b `feMaterial` inputs for `swap_id` (all hex). The returned
/// fields go into the order's `feMaterial` (`refundPubkey`=`claim_pubkey`, no
/// `swapHash`, plus `proofKind:"hashbind"` and the `hashbindProof` the caller
/// computes from `k_be_hex`).
pub fn zwap_z2b_order_inputs(seed_hex: String, swap_id: String) -> Result<ZwapZ2bOrderInputs, String> {
    use secp256k1::{PublicKey, Secp256k1, SecretKey};
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let (_claim_sk, claim_pub) = crate::zwap::dkm::derive_btc_claim_keypair(&seed, &swap_id)?;
    let secp = Secp256k1::new();
    // lock_pubkey = k_a · secp_G (the DLEq/hashbind binding point).
    let k_sk = SecretKey::from_slice(&half.k_be).map_err(|e| format!("k_a as secp scalar: {e}"))?;
    let lock_pubkey = PublicKey::from_secret_key(&secp, &k_sk).serialize();
    Ok(ZwapZ2bOrderInputs {
        h_a: hex::encode(crate::zwap::dkm::hashlock_commit(&half.k_be)),
        ak_a: hex::encode(half.ak_sec1),
        nsk_a: hex::encode(half.nsk_le),
        lock_pubkey: hex::encode(lock_pubkey),
        claim_pubkey: hex::encode(claim_pub),
        k_be_hex: hex::encode(half.k_be),
    })
}

/// Flat, FRB-friendly result of [`zwap_derive_z2b_material`].
pub struct ZwapZ2bMaterial {
    pub btc_lock_address: String,
    pub witness_script_hex: String,
    pub claim_pubkey_hex: String,
    pub joint_zec_address: String,
    pub joint_zec_ufvk: String,
    pub joint_zec_nk_hex: String,
    pub joint_zec_rivk_hex: String,
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    pub swap_hash_hex: String,
    pub h_b_hex: String,
}

/// Derive the z2b material for `swap_id` from the wallet `seed` (hex) and the
/// solver's verified public Phase0 half. `solver_ak_sec1` (66 hex/33B),
/// `solver_nsk_le` (64/32), `solver_h_b` (64/32), `solver_refund_pubkey`
/// (66/33), and `solver_swap_hash` (64/32) come from the recover snapshot /
/// re-verified poold entry. Pure and offline.
#[allow(clippy::too_many_arguments)]
pub fn zwap_derive_z2b_material(
    seed_hex: String,
    swap_id: String,
    solver_ak_sec1: String,
    solver_nsk_le: String,
    solver_h_b: String,
    solver_refund_pubkey: String,
    solver_swap_hash: String,
    t1: u32,
    t2: u32,
    network: String,
) -> Result<ZwapZ2bMaterial, String> {
    use crate::zwap::z2b::{derive_z2b_material, LockTimelocks, SolverPublicHalfZ2b};
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let solver = SolverPublicHalfZ2b {
        ak_sec1: hex33(&solver_ak_sec1, "solver_ak_sec1")?,
        nsk_le: hex32(&solver_nsk_le, "solver_nsk_le")?,
        h_b: hex32(&solver_h_b, "solver_h_b")?,
        refund_pubkey: hex33(&solver_refund_pubkey, "solver_refund_pubkey")?,
        swap_hash: hex32(&solver_swap_hash, "solver_swap_hash")?,
    };
    let m = derive_z2b_material(&seed, &swap_id, &solver, LockTimelocks { t1, t2 }, &network)?;
    Ok(ZwapZ2bMaterial {
        btc_lock_address: m.btc_lock_address,
        witness_script_hex: m.witness_script_hex,
        claim_pubkey_hex: m.claim_pubkey_hex,
        joint_zec_address: m.joint_zec_address,
        joint_zec_ufvk: m.joint_zec_ufvk,
        joint_zec_nk_hex: m.joint_zec_nk_hex,
        joint_zec_rivk_hex: m.joint_zec_rivk_hex,
        joint_zec_ak_hex: m.joint_zec_ak_hex,
        joint_zec_ivk_hex: m.joint_zec_ivk_hex,
        joint_zec_diversifier_hex: m.joint_zec_diversifier_hex,
        swap_hash_hex: m.swap_hash_hex,
        h_b_hex: m.h_b_hex,
    })
}

/// Flat, FRB-friendly signed-tx result.
pub struct ZwapSignedBtcTx {
    pub raw_tx_hex: String,
    pub txid: String,
}

/// Build + sign the z2b BTC branch-1 claim spend of the solver-funded lock,
/// returning the raw tx hex (for esplora `POST /tx` broadcast) + its txid. The
/// user's claim private key and joint scalar `k_be` are re-derived from
/// `(seed, swap_id)` in-Rust (never round-tripped through Dart). `swap_secret`
/// is the value the solver revealed (from the recover snapshot).
#[allow(clippy::too_many_arguments)]
pub fn zwap_sign_z2b_btc_claim_tx(
    seed_hex: String,
    swap_id: String,
    lock_txid: String,
    lock_vout: u32,
    lock_value_sat: u64,
    witness_script_hex: String,
    swap_secret_hex: String,
    dest_spk_hex: String,
    fee_sat: u64,
) -> Result<ZwapSignedBtcTx, String> {
    use crate::zwap::btc_claim::{build_btc_claim_tx, BtcClaimParams};
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let (claim_sk, _claim_pub) = crate::zwap::dkm::derive_btc_claim_keypair(&seed, &swap_id)?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let (raw_tx_hex, txid) = build_btc_claim_tx(&BtcClaimParams {
        lock_txid,
        lock_vout,
        lock_value_sat,
        witness_script_hex,
        claim_sk_be: claim_sk,
        k_b_be: half.k_be,
        swap_secret: hex32(&swap_secret_hex, "swap_secret")?,
        dest_spk_hex,
        fee_sat,
    })?;
    Ok(ZwapSignedBtcTx { raw_tx_hex, txid })
}

// ---------------------------------------------------------------------------
// z2e (ZEC→ETH/USDC) — the EVM give-ZEC direction. The user funds the joint ZEC
// note and CLAIMS a solver-funded singleton ZwapHtlc lock by completing the
// solver's `claim_buy` adaptor with its own `k_be`.
// ---------------------------------------------------------------------------

/// The z2e order `feMaterial` inputs. EVM legs use a Pallas DLEq (not hashbind):
/// `lock_pubkey`+`dleq_proof` are the DLEq material; `claim_pubkey` (the user's
/// per-swap key) is posted as `refundPubkey`; NO `swapHash` (solver-owned).
pub struct ZwapZ2eOrderInputs {
    pub h_a: String,
    pub ak_a: String,
    pub nsk_a: String,
    pub lock_pubkey: String,
    pub dleq_proof: String,
    pub claim_pubkey: String,
    pub k_be_hex: String,
}

/// Assemble the z2e `feMaterial` inputs for `swap_id`. Reuses the e2z DLEq
/// material; adds `claim_pubkey` (`deriveBtcClaimKeypair`) for the `refundPubkey`
/// field and `k_be` (the single-scalar EVM claim key, also the DLEq input).
pub fn zwap_z2e_order_inputs(seed_hex: String, swap_id: String) -> Result<ZwapZ2eOrderInputs, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let (_claim_sk, claim_pub) = crate::zwap::dkm::derive_btc_claim_keypair(&seed, &swap_id)?;
    let proof = crate::zwap::pallas_dleq::prove(&half.k_be).map_err(|e| format!("dleq prove: {e}"))?;
    crate::zwap::pallas_dleq::verify(&proof).map_err(|e| format!("dleq self-verify: {e}"))?;
    Ok(ZwapZ2eOrderInputs {
        h_a: hex::encode(crate::zwap::dkm::hashlock_commit(&half.k_be)),
        ak_a: hex::encode(half.ak_sec1),
        nsk_a: hex::encode(half.nsk_le),
        lock_pubkey: hex::encode(proof.public_key_secp),
        dleq_proof: hex::encode(crate::zwap::pallas_dleq::serialize(&proof)),
        claim_pubkey: hex::encode(claim_pub),
        k_be_hex: hex::encode(half.k_be),
    })
}

/// Flat, FRB-friendly result of [`zwap_derive_z2e_material`].
pub struct ZwapZ2eMaterial {
    pub joint_zec_address: String,
    pub joint_zec_ufvk: String,
    pub joint_zec_nk_hex: String,
    pub joint_zec_rivk_hex: String,
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    pub evm_slot_id_hex: String,
    pub claim_buy_digest_hex: String,
    pub refund_to_initiator_digest_hex: String,
    pub solver_claim_addr_hex: String,
    pub swap_hash_hex: String,
    pub h_b_hex: String,
}

/// Derive the z2e EVM lock + joint-UA material. `token_hex` is the zero address
/// for native ETH (z2e) or the ERC-20 contract (z2erc20). `contract_hex` is the
/// singleton `ZwapHtlc`. `recipient_evm_addr`/`solver_evm_addr` (20-byte hex)
/// come from the recover snapshot; both bind into the slot id.
#[allow(clippy::too_many_arguments)]
pub fn zwap_derive_z2e_material(
    seed_hex: String,
    swap_id: String,
    solver_ak_sec1: String,
    solver_nsk_le: String,
    solver_lock_pubkey: String,
    solver_refund_pubkey: String,
    solver_h_b: String,
    solver_swap_hash: String,
    recipient_evm_addr: String,
    solver_evm_addr: String,
    timelock: u64,
    chain_id: u64,
    contract_hex: String,
    token_hex: String,
    network: String,
) -> Result<ZwapZ2eMaterial, String> {
    use crate::zwap::z2e::{derive_z2e_material, SolverPublicHalfZ2e};
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let solver = SolverPublicHalfZ2e {
        ak_sec1: hex33(&solver_ak_sec1, "solver_ak_sec1")?,
        nsk_le: hex32(&solver_nsk_le, "solver_nsk_le")?,
        lock_pubkey: hex33(&solver_lock_pubkey, "solver_lock_pubkey")?,
        refund_pubkey: hex33(&solver_refund_pubkey, "solver_refund_pubkey")?,
        h_b: hex32(&solver_h_b, "solver_h_b")?,
        swap_hash: hex32(&solver_swap_hash, "solver_swap_hash")?,
    };
    let recipient = hex20(&recipient_evm_addr, "recipient_evm_addr")?;
    let solver_evm = hex20(&solver_evm_addr, "solver_evm_addr")?;
    let contract = hex20(&contract_hex, "contract")?;
    let token = hex20(&token_hex, "token")?;
    let m = derive_z2e_material(
        &seed, &swap_id, &solver, &recipient, &solver_evm, timelock, chain_id, &contract, &token,
        &network,
    )?;
    Ok(ZwapZ2eMaterial {
        joint_zec_address: m.joint_zec_address,
        joint_zec_ufvk: m.joint_zec_ufvk,
        joint_zec_nk_hex: m.joint_zec_nk_hex,
        joint_zec_rivk_hex: m.joint_zec_rivk_hex,
        joint_zec_ak_hex: m.joint_zec_ak_hex,
        joint_zec_ivk_hex: m.joint_zec_ivk_hex,
        joint_zec_diversifier_hex: m.joint_zec_diversifier_hex,
        evm_slot_id_hex: m.evm_slot_id_hex,
        claim_buy_digest_hex: m.claim_buy_digest_hex,
        refund_to_initiator_digest_hex: m.refund_to_initiator_digest_hex,
        solver_claim_addr_hex: m.solver_claim_addr_hex,
        swap_hash_hex: m.swap_hash_hex,
        h_b_hex: m.h_b_hex,
    })
}

/// z2e Phase0 refund pre-share: sign the `refund_to_initiator` digest with the
/// user's per-swap key (`deriveBtcClaimKeypair`, whose address == the slot's
/// `br_B`). The solver assembles its t1 inactivity refund with this + its own
/// adaptor; posting it never cooperates live. Returns the 65-byte sig (hex).
pub fn zwap_z2e_refund_sig_b(
    seed_hex: String,
    swap_id: String,
    refund_to_initiator_digest_hex: String,
) -> Result<String, String> {
    use secp256k1::SecretKey;
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let (claim_sk, _pub) = crate::zwap::dkm::derive_btc_claim_keypair(&seed, &swap_id)?;
    let sk = SecretKey::from_slice(&claim_sk).map_err(|e| format!("claim sk: {e}"))?;
    let digest = hex32(&refund_to_initiator_digest_hex, "refund_to_initiator_digest")?;
    Ok(hex::encode(crate::zwap::evm::sign_eth(&digest, &sk)))
}

/// z2e claim sigs: complete the solver's `claim_buy` adaptor with the user's
/// `k_be` (→ sig_a recovering to `solver_claim_addr`) and sign the digest with
/// `k_be` (→ sig_b, the user's own). Returns both 65-byte sigs (hex); the caller
/// relays them + the preimage to the eth-relayer's `claim_buy`.
pub struct ZwapZ2eClaimSigs {
    pub sig_a_hex: String,
    pub sig_b_hex: String,
}

pub fn zwap_z2e_claim_sigs(
    seed_hex: String,
    swap_id: String,
    adaptor_hex: String,
    claim_buy_digest_hex: String,
    solver_claim_addr_hex: String,
) -> Result<ZwapZ2eClaimSigs, String> {
    use secp256k1::SecretKey;
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let ab = hex::decode(adaptor_hex.trim_start_matches("0x")).map_err(|e| format!("adaptor: bad hex: {e}"))?;
    let adaptor_sig = crate::zwap::adaptor::deserialize(&ab).map_err(|e| format!("adaptor: {e}"))?;
    let digest = hex32(&claim_buy_digest_hex, "claim_buy_digest")?;
    let expected = hex20(&solver_claim_addr_hex, "solver_claim_addr")?;
    let sig_a = crate::zwap::evm::complete_adaptor_eth_sig(&adaptor_sig, &half.k_be, &digest, &expected)
        .ok_or("complete adaptor: no recovery id recovered to the solver claim addr")?;
    let sk = SecretKey::from_slice(&half.k_be).map_err(|e| format!("k_be as sk: {e}"))?;
    let sig_b = crate::zwap::evm::sign_eth(&digest, &sk);
    Ok(ZwapZ2eClaimSigs { sig_a_hex: hex::encode(sig_a), sig_b_hex: hex::encode(sig_b) })
}

/// Decode a segwit BTC address (bech32 v0 p2wpkh/p2wsh, bech32m v1 p2tr) into
/// its `scriptPubKey` hex — the z2b claim payout target the user types in.
pub fn zwap_btc_address_to_spk_hex(address: String) -> Result<String, String> {
    let spk = crate::zwap::bech32_segwit::segwit_address_to_spk(&address)?;
    Ok(hex::encode(spk))
}

/// Decode a unified address (`u1…`/`uregtest1…`/`utest1…`) and return its
/// Orchard receiver as 43-byte raw hex — the `dest_raw_address` the joint-note
/// sweep (`zwap_orchard_spend`) pays to. Errors if the UA has no Orchard
/// receiver.
pub fn zwap_unified_to_orchard_raw_hex(unified_address: String) -> Result<String, String> {
    use zcash_address::unified::{Container, Encoding, Receiver};
    let (_net, ua) = zcash_address::unified::Address::decode(&unified_address)
        .map_err(|e| format!("decode unified address: {e:?}"))?;
    for item in ua.items() {
        if let Receiver::Orchard(raw) = item {
            return Ok(hex::encode(raw));
        }
    }
    Err("unified address has no Orchard receiver".into())
}

/// Build the e2z/z2e `claim_buy` ADAPTOR signature (serialized hex): sign the
/// EIP-191-wrapped `claim_buy_digest` with the wallet's own `k_be` (the buy
/// key, single-scalar reuse), encrypted under the solver's `encryption_point`
/// (its DLEq secp pubkey = the solver `lockPubkey`). The solver completes it
/// with its own `k_be` at claim → reveals `k_solver`, which the wallet then
/// recovers to sweep the joint note. Mirrors the SDK `buildClaimBuyAdaptor`.
pub fn zwap_build_claim_buy_adaptor(
    seed_hex: String,
    swap_id: String,
    encryption_point_hex: String,
    claim_buy_digest_hex: String,
) -> Result<String, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let enc_point = hex33(&encryption_point_hex, "encryption_point")?;
    let digest = hex32(&claim_buy_digest_hex, "claim_buy_digest")?;
    // The adaptor message is the EIP-191-wrapped digest (what the contract's
    // `_recover` checks), NOT the raw domain digest.
    let msg = crate::zwap::evm::eth_signed_hash(&digest);
    let sig = crate::zwap::adaptor::sign(&half.k_be, &enc_point, &msg)
        .map_err(|e| format!("adaptor sign: {e}"))?;
    Ok(hex::encode(crate::zwap::adaptor::serialize(&sig)))
}

/// e2z/z2e sweep recovery: recover the solver's joint-note scalar `k_b`
/// (BE hex) from its on-chain `claim_buy` signature (compact `r‖s`, hex) plus
/// the Phase0 adaptor (serialized hex), selecting the s-malleability candidate
/// whose secp pubkey equals `expected_secp_pubkey_hex` (the solver `lockPubkey`
/// = `k_solver·G_secp`). Errors (never guesses) if neither candidate matches.
pub fn zwap_recover_k_from_claim_sig(
    adaptor_hex: String,
    onchain_sig_hex: String,
    expected_secp_pubkey_hex: String,
) -> Result<String, String> {
    let ab = hex::decode(adaptor_hex.trim_start_matches("0x"))
        .map_err(|e| format!("adaptor: bad hex: {e}"))?;
    let adaptor_sig =
        crate::zwap::adaptor::deserialize(&ab).map_err(|e| format!("adaptor: {e}"))?;
    let sb = hex::decode(onchain_sig_hex.trim_start_matches("0x"))
        .map_err(|e| format!("sig: bad hex: {e}"))?;
    if sb.len() < 64 {
        return Err("onchain sig must be at least 64 bytes (r‖s)".into());
    }
    let mut compact = [0u8; 64];
    compact.copy_from_slice(&sb[..64]);
    let pk = hex33(&expected_secp_pubkey_hex, "expected_secp_pubkey")?;
    let cands = crate::zwap::adaptor::recover_scalar(&adaptor_sig, &compact)
        .map_err(|e| format!("recover_scalar: {e}"))?;
    for cand in cands.iter() {
        if let Ok(p) = crate::zwap::adaptor::public_key_from_secret(cand) {
            if p == pk {
                return Ok(hex::encode(cand));
            }
        }
    }
    Err("no recovered candidate matched the expected secp pubkey".into())
}

/// The e2z/z2e FE proof material — the Pallas DLEq that EVM-leg swaps require
/// (instead of the b2z hashbind SNARK). Binds `ak_a` (Orchard SpendAuth point,
/// = the FE's lock pubkey on Pallas) to the secp lock pubkey `k_a·G_secp`.
pub struct ZwapDleqMaterial {
    /// The secp lock pubkey `k_a·G_secp` (33-byte compressed hex) — the
    /// feMaterial `lockPubkey` for `proofKind='dleq'`.
    pub lock_pubkey_secp_hex: String,
    /// The serialized Pallas DLEq proof (hex) — the feMaterial `hashbindProof`.
    pub dleq_proof_hex: String,
}

/// Build the e2z/z2e DLEq feMaterial for `swap_id`. Self-verifies the proof
/// (the matcher re-runs `verify`; committing an unverifiable proof would strand
/// a funded swap) and asserts the DLEq Pallas point equals the derived `ak_a`.
pub fn zwap_e2z_dleq_material(
    seed_hex: String,
    swap_id: String,
) -> Result<ZwapDleqMaterial, String> {
    let seed = hex::decode(&seed_hex).map_err(|e| format!("seed: bad hex: {e}"))?;
    let half = crate::zwap::dkm::derive_initiator_half(&seed, &swap_id)?;
    let proof = crate::zwap::pallas_dleq::prove(&half.k_be)
        .map_err(|e| format!("dleq prove: {e}"))?;
    let verified = crate::zwap::pallas_dleq::verify(&proof)
        .map_err(|e| format!("dleq self-verify: {e}"))?;
    // The advertised `akA` is the derived ak_a; the DLEq Pallas witness MUST
    // equal it (SpendAuth generator) or the matcher rejects.
    if verified.public_key_pallas != half.ak_sec1 {
        return Err("dleq: recovered K_p != derived ak_a".into());
    }
    Ok(ZwapDleqMaterial {
        lock_pubkey_secp_hex: hex::encode(proof.public_key_secp),
        dleq_proof_hex: hex::encode(crate::zwap::pallas_dleq::serialize(&proof)),
    })
}
