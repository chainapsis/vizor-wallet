//! EVM leg for e2z (ETH→ZEC) swaps, including the **proxy (counterfactual
//! CREATE2 deposit)** variant the `feat/v3-reserve-e2z-proxy` branch adds.
//!
//! Two halves, both pure (no chain I/O):
//! - **HTLC digest/signature core** — vendored from `solver-v3/src/evm_htlc.rs`
//!   (keccak256 domain digests + recoverable ECDSA, byte-pinned to
//!   `ZwapHtlc.sol` golden vectors).
//! - **Proxy CREATE2 derivation** — ported from the SDK `proxyTerms.ts`
//!   (`abiEncodeSwapTerms` / `proxySalt` / `computeProxyAddress` /
//!   `proxyDigest`). The user derives the deposit address **locally** from the
//!   pinned creation bytecode — never solver-trusted (fund-safety).
//!
//! In deposit-based e2z the wallet shows the derived proxy address and the user
//! funds it from their own ETH wallet (partial top-ups allowed); the solver
//! deploys the proxy + claims. The wallet signs only the EVM refund/adaptor
//! digests (unhappy path) with a seed-derived secp256k1 key.

use secp256k1::ecdsa::{RecoverableSignature, RecoveryId};
use secp256k1::{Message, PublicKey, Secp256k1, SecretKey};
use sha2::{Digest as _, Sha256};
use sha3::{Digest, Keccak256};

/// EIP-1167 minimal-proxy init code, split around the 20-byte implementation
/// address: `PREFIX ‖ impl(20) ‖ SUFFIX` (OpenZeppelin `Clones`). The per-swap
/// escrow is a minimal proxy delegatecalling the one `HtlcProxy` implementation,
/// so the deposit-address init code is standard + fixed; only the implementation
/// address (a per-chain deploy) varies, supplied at derivation.
const EIP1167_INITCODE_PREFIX: &str = "3d602d80600a3d3981f3363d3d373d3d3d363d73";
const EIP1167_INITCODE_SUFFIX: &str = "5af43d82803e903d91602b57fd5bf3";

/// Domain tags (must match `ZwapHtlc` / `HtlcProxy` `_*Digest`).
pub const DOMAIN_CLAIM_BUY: &str = "ZwapHtlc.v1.claim_buy";
pub const DOMAIN_REFUND_TO_INITIATOR: &str = "ZwapHtlc.v1.refund_to_initiator";
pub const DOMAIN_REFUND_AFTER_CLAIM: &str = "ZwapHtlc.v1.refund_after_claim";

fn keccak(parts: &[&[u8]]) -> [u8; 32] {
    let mut h = Keccak256::new();
    for p in parts {
        h.update(p);
    }
    h.finalize().into()
}

/// A 32-byte big-endian ABI word from a u128 (amount / deadline / chainId).
fn word_u256(v: u128) -> [u8; 32] {
    let mut w = [0u8; 32];
    w[16..].copy_from_slice(&v.to_be_bytes());
    w
}

/// A 20-byte address left-padded into a 32-byte ABI word.
fn word_address(a: &[u8; 20]) -> [u8; 32] {
    let mut w = [0u8; 32];
    w[12..].copy_from_slice(a);
    w
}

// ---------------------------------------------------------------------------
// Singleton HTLC digest/signature core (vendored from evm_htlc.rs).
// ---------------------------------------------------------------------------

/// `keccak256(domain ‖ uint256(chainId) ‖ address(contract) ‖ bytes32(slotId))`.
pub fn htlc_digest(domain: &str, chain_id: u64, contract: &[u8; 20], slot_id: &[u8; 32]) -> [u8; 32] {
    keccak(&[domain.as_bytes(), &word_u256(chain_id as u128), contract, slot_id])
}

/// `keccak256(swap_hash ‖ b_A ‖ b_B ‖ buyer ‖ initiator ‖ uint64(timelock) ‖ token)`.
#[allow(clippy::too_many_arguments)]
pub fn slot_id(
    swap_hash: &[u8; 32],
    b_a: &[u8; 20],
    b_b: &[u8; 20],
    buyer: &[u8; 20],
    initiator: &[u8; 20],
    timelock: u64,
    token: &[u8; 20],
) -> [u8; 32] {
    keccak(&[swap_hash, b_a, b_b, buyer, initiator, &timelock.to_be_bytes(), token])
}

/// `keccak256("\x19Ethereum Signed Message:\n32" ‖ digest)` — the EIP-191 hash
/// the contract's `_recover` checks against.
pub fn eth_signed_hash(digest: &[u8; 32]) -> [u8; 32] {
    keccak(&[b"\x19Ethereum Signed Message:\n32", digest])
}

/// Sign a 32-byte domain digest → Ethereum 65-byte `r ‖ s ‖ v` (`v ∈ {27,28}`).
pub fn sign_eth(digest: &[u8; 32], sk: &SecretKey) -> [u8; 65] {
    let sig = Secp256k1::new().sign_ecdsa_recoverable(&Message::from_digest(eth_signed_hash(digest)), sk);
    let (recid, compact) = sig.serialize_compact();
    let mut out = [0u8; 65];
    out[..64].copy_from_slice(&compact);
    out[64] = 27 + recid.to_i32() as u8;
    out
}

/// The Ethereum address of a public key: `keccak256(uncompressed[1..])[12..]`.
pub fn eth_address(pk: &PublicKey) -> [u8; 20] {
    let uncompressed = pk.serialize_uncompressed();
    let h = Keccak256::digest(&uncompressed[1..]);
    let mut addr = [0u8; 20];
    addr.copy_from_slice(&h[12..]);
    addr
}

/// Recover the signer address from a digest + 65-byte sig (mirrors `_recover`).
pub fn recover_address(digest: &[u8; 32], sig65: &[u8; 65]) -> Result<[u8; 20], String> {
    let recid = RecoveryId::from_i32((sig65[64] as i32) - 27).map_err(|e| format!("recid: {e}"))?;
    let sig = RecoverableSignature::from_compact(&sig65[..64], recid).map_err(|e| format!("sig: {e}"))?;
    let pk = Secp256k1::new()
        .recover_ecdsa(&Message::from_digest(eth_signed_hash(digest)), &sig)
        .map_err(|e| format!("recover: {e}"))?;
    Ok(eth_address(&pk))
}

/// z2e USER side: complete the SOLVER's `claim_buy` ASMR adaptor with the user's
/// own `k_be` (single-scalar reuse) → the on-chain 65-byte `claim_buy` sig_a that
/// the contract recovers to the solver's claim address `expected_signer` (the
/// solver's `b_a`). Broadcasting it reveals the user's `k_user`, which the solver
/// then uses to drain the joint ZEC note. Byte-exact mirror of the solver's
/// `evm_adaptor::complete_adaptor_eth_sig` (the e2z operation, run by the user in
/// z2e). Returns `None` if neither recovery id recovers to the expected signer.
pub fn complete_adaptor_eth_sig(
    adaptor_sig: &crate::zwap::adaptor::AdaptorSignature,
    decryption_k_be: &[u8; 32],
    claim_buy_digest: &[u8; 32],
    expected_signer: &[u8; 20],
) -> Option<[u8; 65]> {
    let compact = crate::zwap::adaptor::decrypt(adaptor_sig, decryption_k_be).ok()?;
    let msg = Message::from_digest(eth_signed_hash(claim_buy_digest));
    let secp = Secp256k1::new();
    for recid in 0..2i32 {
        let rid = RecoveryId::from_i32(recid).ok()?;
        let sig = RecoverableSignature::from_compact(&compact, rid).ok()?;
        if let Ok(pk) = secp.recover_ecdsa(&msg, &sig) {
            if &eth_address(&pk) == expected_signer {
                let mut out = [0u8; 65];
                out[..64].copy_from_slice(&compact);
                out[64] = 27 + recid as u8;
                return Some(out);
            }
        }
    }
    None
}

/// The contract hashlock check: `sha256(preimage) == swap_hash`.
pub fn hashlock_ok(preimage: &[u8; 32], swap_hash: &[u8; 32]) -> bool {
    let h: [u8; 32] = Sha256::digest(preimage).into();
    &h == swap_hash
}

// ---------------------------------------------------------------------------
// e2z PROXY (CREATE2 counterfactual deposit) — local derivation.
// ---------------------------------------------------------------------------

/// The per-swap proxy parameters. Field ORDER + types MUST match the Solidity
/// `SwapTerms` struct and the SDK `proxyTerms.ts` (order-sensitive ABI encode).
#[derive(Clone, Debug)]
pub struct SwapTerms {
    pub token: [u8; 20], // zero address = native ETH
    pub amount: u128,
    pub buyer: [u8; 20],     // solver payout
    pub initiator: [u8; 20], // user refund
    pub b_a: [u8; 20],
    pub b_b: [u8; 20],
    pub br_a: [u8; 20],
    pub br_b: [u8; 20],
    pub swap_hash: [u8; 32],
    pub h_b: [u8; 32],
    pub t0_abs: u128,
    pub t1_abs: u128,
    pub chain_id: u128,
    pub factory: [u8; 20],
}

/// `abi.encode(SwapTerms)` — 14 static 32-byte words in struct order.
pub fn abi_encode_swap_terms(t: &SwapTerms) -> Vec<u8> {
    let mut out = Vec::with_capacity(14 * 32);
    out.extend_from_slice(&word_address(&t.token));
    out.extend_from_slice(&word_u256(t.amount));
    out.extend_from_slice(&word_address(&t.buyer));
    out.extend_from_slice(&word_address(&t.initiator));
    out.extend_from_slice(&word_address(&t.b_a));
    out.extend_from_slice(&word_address(&t.b_b));
    out.extend_from_slice(&word_address(&t.br_a));
    out.extend_from_slice(&word_address(&t.br_b));
    out.extend_from_slice(&t.swap_hash);
    out.extend_from_slice(&t.h_b);
    out.extend_from_slice(&word_u256(t.t0_abs));
    out.extend_from_slice(&word_u256(t.t1_abs));
    out.extend_from_slice(&word_u256(t.chain_id));
    out.extend_from_slice(&word_address(&t.factory));
    out
}

/// `salt = keccak256(abi.encode(SwapTerms))` — CREATE2 salt + slotId analog.
pub fn proxy_salt(t: &SwapTerms) -> [u8; 32] {
    keccak(&[&abi_encode_swap_terms(t)])
}

/// The EIP-1167 minimal-proxy init code for `implementation`:
/// `PREFIX ‖ impl(20) ‖ SUFFIX`.
fn eip1167_init_code(implementation: &[u8; 20]) -> Vec<u8> {
    let mut hex_str = String::with_capacity(EIP1167_INITCODE_PREFIX.len() + 40 + EIP1167_INITCODE_SUFFIX.len());
    hex_str.push_str(EIP1167_INITCODE_PREFIX);
    hex_str.push_str(&hex::encode(implementation));
    hex_str.push_str(EIP1167_INITCODE_SUFFIX);
    hex::decode(hex_str).expect("static EIP-1167 hex is valid")
}

/// LOCAL CREATE2 deposit address (EIP-1167 minimal proxy):
/// `keccak256(0xff ‖ factory(20) ‖ salt ‖ keccak256(eip1167InitCode(impl)))[12..]`,
/// `salt = keccak256(abi.encode(terms))`. The escrow is an OZ `Clones` minimal
/// proxy over `implementation` (a per-chain deploy), so init code is standard.
/// Derived locally — never trusted from the solver.
pub fn compute_proxy_address(t: &SwapTerms, implementation: &[u8; 20]) -> [u8; 20] {
    let salt = proxy_salt(t);
    let init_code_hash = keccak(&[&eip1167_init_code(implementation)]);
    let pre_addr = keccak(&[&[0xffu8], &t.factory[..], &salt, &init_code_hash]);
    let mut addr = [0u8; 20];
    addr.copy_from_slice(&pre_addr[12..]);
    addr
}

/// The proxy settlement digest:
/// `keccak256(domain ‖ uint256(chainId) ‖ proxyAddr(20) ‖ salt(32))`.
pub fn proxy_digest(domain: &str, chain_id: u64, proxy_addr: &[u8; 20], salt: &[u8; 32]) -> [u8; 32] {
    keccak(&[domain.as_bytes(), &word_u256(chain_id as u128), proxy_addr, salt])
}

// ---------------------------------------------------------------------------
// Seed-derived EVM key (user refund / adaptor signer for the e2z leg).
// ---------------------------------------------------------------------------

/// Derive the user's per-swap EVM secp256k1 key from `(seed, swap_id)`:
/// `priv = SHA256(seed ‖ "zwap-v3-evm-refund:" ‖ swap_id)` (resalted on the
/// vanishingly-rare invalid scalar). Returns the key + its 20-byte eth address.
pub fn derive_evm_refund_key(seed: &[u8], swap_id: &str) -> Result<(SecretKey, [u8; 20]), String> {
    for i in 0u16..256 {
        let mut h = Sha256::new();
        h.update(seed);
        h.update(format!("zwap-v3-evm-refund:{swap_id}:{i}").as_bytes());
        if let Ok(sk) = SecretKey::from_slice(&h.finalize()) {
            let pk = PublicKey::from_secret_key(&Secp256k1::new(), &sk);
            let addr = eth_address(&pk);
            return Ok((sk, addr));
        }
    }
    Err("no valid secp256k1 EVM key in 256 tries (cryptographically impossible)".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use secp256k1::rand::rngs::OsRng;

    fn a20(h: &str) -> [u8; 20] {
        hex::decode(h).unwrap().try_into().unwrap()
    }
    // Matches the golden's helper in eth_tx.rs: only the LAST byte is set.
    fn h32(byte: u8) -> [u8; 32] {
        let mut x = [0u8; 32];
        x[31] = byte;
        x
    }

    /// GOLDEN (from evm_htlc.rs): digest byte layout matches Solidity abi.encodePacked.
    #[test]
    fn htlc_digest_matches_solidity_golden() {
        let d = htlc_digest(DOMAIN_CLAIM_BUY, 31337, &[0x11; 20], &[0x22; 32]);
        assert_eq!(hex::encode(d), "1ee45cfef9357d05c8f13beaed9f4f4b4fd093822d13c9138b75034430c16ab1");
    }

    #[test]
    fn slot_id_matches_solidity_golden() {
        let s = slot_id(&[0x11; 32], &[0x22; 20], &[0x33; 20], &[0x44; 20], &[0x55; 20], 100, &[0x00; 20]);
        assert_eq!(hex::encode(s), "bf06f5488db025f3f2f1f0cffe1fad7199415497fdfc87835fd4c70cffa9c40c");
    }

    #[test]
    fn sign_then_recover_round_trips() {
        let secp = Secp256k1::new();
        let sk = SecretKey::new(&mut OsRng);
        let addr = eth_address(&PublicKey::from_secret_key(&secp, &sk));
        let digest = htlc_digest(DOMAIN_CLAIM_BUY, 31337, &[0xab; 20], &[0xcd; 32]);
        let sig = sign_eth(&digest, &sk);
        assert!(sig[64] == 27 || sig[64] == 28);
        assert_eq!(recover_address(&digest, &sig).unwrap(), addr);
    }

    /// The golden ProxyTerms from `eth_tx.rs::proxy_salt_matches_sdk_golden`.
    fn golden_terms() -> SwapTerms {
        SwapTerms {
            token: [0u8; 20],
            amount: 1_000_000_000_000_000_000u128,
            buyer: a20("1111111111111111111111111111111111111111"),
            initiator: a20("2222222222222222222222222222222222222222"),
            b_a: a20("3333333333333333333333333333333333333333"),
            b_b: a20("4444444444444444444444444444444444444444"),
            br_a: a20("5555555555555555555555555555555555555555"),
            br_b: a20("6666666666666666666666666666666666666666"),
            swap_hash: h32(0xAA),
            h_b: h32(0xBB),
            t0_abs: 1000,
            t1_abs: 2000,
            chain_id: 31337,
            factory: a20("5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f"),
        }
    }

    /// PARITY: salt matches the SDK/Solidity golden — a drift misdirects the deposit (fund loss).
    #[test]
    fn proxy_salt_matches_sdk_golden() {
        assert_eq!(
            hex::encode(proxy_salt(&golden_terms())),
            "40479acf5368321f95d017ffabfce910f2111f6c7b53391c111a70b6a3aaaa17"
        );
    }

    /// PARITY: the LOCAL EIP-1167 CREATE2 deposit address matches the golden the
    /// SDK `computeProxyAddress` produces (generated from the branch's own code
    /// for `implementation = 0x…beef`). Proves the minimal-proxy init code +
    /// CREATE2 encoding match — a drift misdirects the user's ETH deposit.
    #[test]
    fn compute_proxy_address_matches_golden() {
        let impl_addr: [u8; 20] = a20("000000000000000000000000000000000000beef");
        let addr = compute_proxy_address(&golden_terms(), &impl_addr);
        assert_eq!(hex::encode(addr), "69fcbe4f0a9d4e21934930f76e250c0c47f58e86");
    }

    /// PARITY: proxy claim_buy digest matches the SDK/Solidity golden.
    #[test]
    fn proxy_digest_matches_golden() {
        let salt = proxy_salt(&golden_terms());
        let proxy_addr = a20("e812fdbf05501f0af0fad01b30f019a8c1279fb0");
        assert_eq!(
            hex::encode(proxy_digest(DOMAIN_CLAIM_BUY, 31337, &proxy_addr, &salt)),
            "640178f360b8523a499605273d1eba37ec4b93ffc4b7fd4103d1e9fcae3f738c"
        );
    }

    #[test]
    fn evm_refund_key_is_deterministic() {
        let seed = [9u8; 32];
        let (_sk, addr) = derive_evm_refund_key(&seed, "swap-e2z-1").unwrap();
        let (_sk2, addr2) = derive_evm_refund_key(&seed, "swap-e2z-1").unwrap();
        assert_eq!(addr, addr2);
        let (_sk3, addr3) = derive_evm_refund_key(&seed, "swap-e2z-2").unwrap();
        assert_ne!(addr, addr3);
    }
}
