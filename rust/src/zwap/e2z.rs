//! e2z (ETH→ZEC) **proxy** initiator material assembly — the pure, stateless
//! step that turns `(seed, swap_id)` + the solver's relayed half + proxy terms
//! into the artifacts a deposit-based e2z swap presents:
//!
//! 1. the **CREATE2 proxy deposit address** the user funds with ETH (derived
//!    LOCALLY from pinned creation bytecode — never solver-trusted), and
//! 2. the **joint ZEC unified address** the user later sweeps.
//!
//! Role map (e2z): the user is the Initiator (funds ETH); the solver receives +
//! claims. The user's DKM scalar `k_be` doubles as its EVM claim key (`bB`);
//! `brB` is the seed-derived refund key as an eth address; `initiator` is the
//! user's own ETH wallet (the t1 refund destination), supplied by the caller.
//! Mirrors the SDK `buildInitiatorEvmPhase0` proxy branch (`handshake.ts`).

use secp256k1::{PublicKey, Secp256k1, SecretKey};
use sha2::{Digest, Sha256};

use super::dkm::{derive_initiator_half, derive_swap_secret, hashlock_commit};
use super::evm::{
    compute_proxy_address, eth_address, proxy_digest, proxy_salt, SwapTerms, DOMAIN_CLAIM_BUY,
    DOMAIN_REFUND_AFTER_CLAIM, DOMAIN_REFUND_TO_INITIATOR,
};
use super::joint_orchard::{derive_joint_orchard, ZecNetwork};

/// The solver's relayed public contribution for an e2z proxy swap (after the
/// wallet has re-verified the backing poold proof).
#[derive(Clone, Debug)]
pub struct E2zSolverHalf {
    /// `ak_b` SEC1 (33 bytes) — joint ZEC UA.
    pub ak_sec1: [u8; 33],
    /// `nsk_b` LE (32 bytes) — joint ZEC UA.
    pub nsk_le: [u8; 32],
    /// Solver's EVM claim/lock pubkey (33-byte compressed secp256k1) → `bA`.
    pub lock_pubkey: [u8; 33],
    /// Solver's EVM refund pubkey (33-byte compressed secp256k1) → `brA`.
    pub refund_pubkey: [u8; 33],
    /// `h_b = SHA256(k_b)`.
    pub h_b: [u8; 32],
    /// The solver's EVM home address (20 bytes) — the `buyer` (claim recipient).
    pub solver_evm_addr: [u8; 20],
}

/// The proxy escrow terms the solver relays (absolute-block deadlines etc).
#[derive(Clone, Debug)]
pub struct E2zProxyTerms {
    /// Locked amount (wei for ETH, token units for ERC20).
    pub amount: u128,
    /// ERC20 token address, or the zero address for native ETH.
    pub token: [u8; 20],
    pub t0_abs: u128,
    pub t1_abs: u128,
    pub chain_id: u128,
    /// The proxy factory address.
    pub factory: [u8; 20],
    /// The shared HtlcProxy implementation address (EIP-1167 clone target); a
    /// per-chain deploy relayed by the solver. Baked into the deposit address.
    pub implementation: [u8; 20],
}

/// The assembled, displayable e2z proxy material.
#[derive(Clone, Debug)]
pub struct E2zMaterial {
    /// The CREATE2 proxy deposit address (0x-hex) the user funds with ETH.
    pub deposit_address: String,
    /// The proxy CREATE2 salt (0x-hex) = the slotId analog.
    pub salt_hex: String,
    /// claim_buy / refund_to_initiator / refund_after_claim digests (0x-hex).
    pub claim_buy_digest: String,
    pub refund_to_initiator_digest: String,
    pub refund_after_claim_digest: String,
    /// The joint Orchard unified address the user sweeps.
    pub joint_zec_address: String,
    pub joint_zec_ufvk: String,
    /// Joint Orchard `nk`/`rivk` (32-byte hex) — required to build the sweep.
    pub joint_zec_nk_hex: String,
    pub joint_zec_rivk_hex: String,
    /// Joint `ak`/`ivk` (32-byte hex) + `diversifier` (11-byte hex) — for local
    /// trial-decryption of the joint note.
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    /// `swap_hash = SHA256(secret)` (hex, no 0x).
    pub swap_hash_hex: String,
    /// The canonical `proxyTerms` JSON posted to the OB at Phase0 (keys/encodings
    /// match the solver's `parse_proxy_terms_json` + the indexer).
    pub proxy_terms_json: String,
}

fn parse_addr20(hex_str: &str) -> [u8; 20] {
    hex::decode(hex_str.trim_start_matches("0x"))
        .expect("valid pinned addr hex")
        .try_into()
        .expect("20-byte pinned addr")
}

/// Pinned per-chain `(factory, implementation)` for the HtlcProxy — the CREATE2
/// deployer + the EIP-1167 delegatecall target. These are deployment constants
/// (the FE pins them via `VITE_PROXY_FACTORY`/`VITE_PROXY_IMPLEMENTATION`); the
/// wallet must NOT accept them from the solver. Mainnet/other chains must be
/// filled in with the real deploy before enabling e2z there (fail-closed until).
pub fn pinned_proxy_contracts(chain_id: u128) -> Result<([u8; 20], [u8; 20]), String> {
    match chain_id {
        // Local regtest anvil (deterministic fresh-chain deploy — see v3/up.sh).
        31337 => Ok((
            parse_addr20("057ef64E23666F000b34aE31332854aCBd1c8544"),
            parse_addr20("3b3112c4376d037822DECFf3Fe6CD30E1E726517"),
        )),
        other => Err(format!(
            "e2z: no pinned proxy factory/implementation for chain {other} \
             (must be set before enabling e2z on this chain)"
        )),
    }
}

fn eth_addr_from_pubkey(sec1: &[u8; 33]) -> Result<[u8; 20], String> {
    let pk = PublicKey::from_slice(sec1).map_err(|e| format!("pubkey: {e}"))?;
    Ok(eth_address(&pk))
}

/// The user's EVM claim address `bB` = eth address of the DKM scalar `k_be`
/// (used directly as a secp256k1 key — the single-scalar cross-curve reuse the
/// DLEq proof binds). `k_be` is < 2^251 (safe id), always a valid secp key.
fn eth_addr_from_scalar_be(k_be: &[u8; 32]) -> Result<[u8; 20], String> {
    let sk = SecretKey::from_slice(k_be).map_err(|e| format!("k_be as secp key: {e}"))?;
    let pk = PublicKey::from_secret_key(&Secp256k1::new(), &sk);
    Ok(eth_address(&pk))
}

/// The user's seed-derived refund pubkey (`SHA256(seed ‖ 0x42)`), as an eth
/// address (`brB`). Same key the b2z BTC refund path uses.
fn eth_addr_user_refund(seed: &[u8]) -> Result<[u8; 20], String> {
    let mut h = Sha256::new();
    h.update(seed);
    h.update([0x42]);
    let sk = SecretKey::from_slice(&h.finalize()).map_err(|e| format!("refund key: {e}"))?;
    let pk = PublicKey::from_secret_key(&Secp256k1::new(), &sk);
    Ok(eth_address(&pk))
}

fn addr_hex(a: &[u8; 20]) -> String {
    format!("0x{}", hex::encode(a))
}

fn map_network(network: &str) -> ZecNetwork {
    match network {
        "mainnet" | "main" => ZecNetwork::Mainnet,
        "testnet" | "test" => ZecNetwork::Testnet,
        _ => ZecNetwork::Regtest,
    }
}

/// Assemble the e2z proxy initiator material. `initiator_evm_addr` is the user's
/// own ETH wallet (the t1 refund destination). `network` selects the ZEC UA HRP.
pub fn derive_e2z_proxy_material(
    seed: &[u8],
    swap_id: &str,
    solver: &E2zSolverHalf,
    proxy: &E2zProxyTerms,
    initiator_evm_addr: [u8; 20],
    network: &str,
) -> Result<E2zMaterial, String> {
    let half = derive_initiator_half(seed, swap_id)?;
    let secret = derive_swap_secret(seed, swap_id);
    let swap_hash = hashlock_commit(&secret);

    // FUND-SAFETY (#2): the CREATE2 deposit address folds in the `factory` (part
    // of the salt) and the EIP-1167 `implementation` (delegatecall target). Both
    // MUST be pinned per-chain constants — never solver-supplied — or a malicious
    // implementation drains the deposit. We use the pinned pair and reject any
    // relayed value that disagrees (fail-closed), matching the FE's
    // `VITE_PROXY_FACTORY`/`VITE_PROXY_IMPLEMENTATION` pinning.
    let (factory, implementation) = pinned_proxy_contracts(proxy.chain_id)?;
    if proxy.factory != factory {
        return Err(format!(
            "e2z: relayed factory {} != pinned {} for chain {}",
            addr_hex(&proxy.factory), addr_hex(&factory), proxy.chain_id
        ));
    }
    if proxy.implementation != implementation {
        return Err(format!(
            "e2z: relayed implementation {} != pinned {} for chain {}",
            addr_hex(&proxy.implementation), addr_hex(&implementation), proxy.chain_id
        ));
    }

    // EVM role map (e2z): b_a/br_a = solver, b_b/br_b = user; buyer = solver home.
    let b_a = eth_addr_from_pubkey(&solver.lock_pubkey)?;
    let b_b = eth_addr_from_scalar_be(&half.k_be)?;
    let br_a = eth_addr_from_pubkey(&solver.refund_pubkey)?;
    let br_b = eth_addr_user_refund(seed)?;
    let buyer = solver.solver_evm_addr;

    let terms = SwapTerms {
        token: proxy.token,
        amount: proxy.amount,
        buyer,
        initiator: initiator_evm_addr,
        b_a,
        b_b,
        br_a,
        br_b,
        swap_hash,
        h_b: solver.h_b,
        t0_abs: proxy.t0_abs,
        t1_abs: proxy.t1_abs,
        chain_id: proxy.chain_id,
        factory, // pinned, not relayed
    };

    let salt = proxy_salt(&terms);
    let deposit = compute_proxy_address(&terms, &implementation); // pinned impl
    let chain_id_u64 = proxy.chain_id as u64;

    // Joint ZEC UA (re-derived from both halves — never trusted from the wire).
    let joint = derive_joint_orchard(
        &half.ak_sec1,
        &solver.ak_sec1,
        &half.nsk_le,
        &solver.nsk_le,
        map_network(network),
    )?;

    let proxy_terms_json = serde_json::json!({
        "token": addr_hex(&terms.token),
        "amount": terms.amount.to_string(),
        "buyer": addr_hex(&buyer),
        "initiator": addr_hex(&initiator_evm_addr),
        "bA": addr_hex(&b_a),
        "bB": addr_hex(&b_b),
        "brA": addr_hex(&br_a),
        "brB": addr_hex(&br_b),
        "swapHash": format!("0x{}", hex::encode(swap_hash)),
        "hB": format!("0x{}", hex::encode(solver.h_b)),
        "t0Abs": terms.t0_abs.to_string(),
        "t1Abs": terms.t1_abs.to_string(),
        "chainId": terms.chain_id.to_string(),
        "factory": addr_hex(&terms.factory),
        "proxyAddr": addr_hex(&deposit),
    })
    .to_string();

    Ok(E2zMaterial {
        deposit_address: addr_hex(&deposit),
        salt_hex: format!("0x{}", hex::encode(salt)),
        claim_buy_digest: format!("0x{}", hex::encode(proxy_digest(DOMAIN_CLAIM_BUY, chain_id_u64, &deposit, &salt))),
        refund_to_initiator_digest: format!(
            "0x{}",
            hex::encode(proxy_digest(DOMAIN_REFUND_TO_INITIATOR, chain_id_u64, &deposit, &salt))
        ),
        refund_after_claim_digest: format!(
            "0x{}",
            hex::encode(proxy_digest(DOMAIN_REFUND_AFTER_CLAIM, chain_id_u64, &deposit, &salt))
        ),
        joint_zec_address: joint.deposit_address,
        joint_zec_ufvk: joint.joint_ufvk_encoded,
        joint_zec_nk_hex: hex::encode(joint.nk),
        joint_zec_rivk_hex: hex::encode(joint.rivk),
        joint_zec_ak_hex: hex::encode(joint.ak),
        joint_zec_ivk_hex: hex::encode(joint.ivk),
        joint_zec_diversifier_hex: hex::encode(joint.diversifier),
        swap_hash_hex: hex::encode(swap_hash),
        proxy_terms_json,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zwap::dkm::derive_initiator_half as solver_like_half;

    fn synth_solver(seed: &[u8], swap_id: &str) -> E2zSolverHalf {
        let h = solver_like_half(seed, swap_id).unwrap();
        // A throwaway compressed secp pubkey for the solver's EVM keys.
        let sk = SecretKey::from_slice(&h.k_be).unwrap();
        let pk = PublicKey::from_secret_key(&Secp256k1::new(), &sk).serialize();
        E2zSolverHalf {
            ak_sec1: h.ak_sec1,
            nsk_le: h.nsk_le,
            lock_pubkey: pk,
            refund_pubkey: pk,
            h_b: crate::zwap::dkm::hashlock_commit(&h.k_be),
            solver_evm_addr: [0xabu8; 20],
        }
    }

    #[test]
    fn derives_deposit_and_joint_ua_regtest() {
        let seed = [9u8; 32];
        let solver = synth_solver(&[5u8; 32], "swap-e2z-1");
        let proxy = E2zProxyTerms {
            amount: 1_000_000_000_000_000_000u128,
            token: [0u8; 20],
            t0_abs: 1000,
            t1_abs: 2000,
            chain_id: 31337,
            // Must equal the pinned regtest constants or the fund-safety gate rejects.
            factory: super::pinned_proxy_contracts(31337).unwrap().0,
            implementation: super::pinned_proxy_contracts(31337).unwrap().1,
        };
        let m = derive_e2z_proxy_material(&seed, "swap-e2z-1", &solver, &proxy, [0x22u8; 20], "regtest").unwrap();

        assert!(m.deposit_address.starts_with("0x") && m.deposit_address.len() == 42, "eth deposit addr");
        assert!(m.joint_zec_address.starts_with("uregtest1"), "joint ZEC UA: {}", m.joint_zec_address);
        assert!(m.joint_zec_ufvk.starts_with("uview"));
        assert_eq!(m.joint_zec_nk_hex.len(), 64);
        assert_eq!(m.joint_zec_rivk_hex.len(), 64);
        assert!(m.proxy_terms_json.contains("\"proxyAddr\":\"0x"));
        // Deterministic.
        let m2 = derive_e2z_proxy_material(&seed, "swap-e2z-1", &solver, &proxy, [0x22u8; 20], "regtest").unwrap();
        assert_eq!(m.deposit_address, m2.deposit_address);
    }

    #[test]
    fn rejects_unpinned_factory_or_implementation() {
        let solver = synth_solver(&[5u8; 32], "swap-e2z-2");
        let bad = E2zProxyTerms {
            amount: 1,
            token: [0u8; 20],
            t0_abs: 1,
            t1_abs: 2,
            chain_id: 31337,
            factory: [0x99u8; 20], // not pinned
            implementation: super::pinned_proxy_contracts(31337).unwrap().1,
        };
        assert!(derive_e2z_proxy_material(&[9u8; 32], "swap-e2z-2", &solver, &bad, [0x22u8; 20], "regtest")
            .unwrap_err()
            .contains("factory"));
    }
}
