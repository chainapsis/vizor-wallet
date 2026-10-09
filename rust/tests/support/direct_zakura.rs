//! Direct funding through the original case controller, without file handoffs.
use serde::Deserialize;
use std::path::Path;

pub const NETWORK: &str = "regtest";
pub const AMOUNT_ZATOSHI: u64 = 100_000_000;
pub const REQUIRED_CONFIRMATIONS: u32 = 6;

pub struct DirectZakuraEnvironment {
    pub lightwalletd_url: String,
    pub initial_tip_height: u64,
}

// The host also returns retained source/conservation/raw/compact inclusion
// proofs. Read only these observation fields, not a caller-provided PASS flag.
#[derive(Deserialize)]
pub struct FundingResponse {
    pub schema_version: u32,
    pub txid_hex: String,
    pub amount_zatoshi: u64,
    pub mined_height: u64,
    pub final_tip_height: u64,
    pub confirmations: u32,
    pub pool: String,
}

pub fn required_environment() -> DirectZakuraEnvironment {
    crate::common::require_isolated_regtest();
    DirectZakuraEnvironment {
        lightwalletd_url: crate::common::lightwalletd_url(),
        initial_tip_height: crate::common::current_tip_height(),
    }
}

pub fn fund_wallet(environment: &DirectZakuraEnvironment, address: &str) -> FundingResponse {
    assert_eq!(
        crate::common::current_tip_height(),
        environment.initial_tip_height
    );
    serde_json::from_value(crate::common::fund_isolated_wallet(
        address,
        AMOUNT_ZATOSHI,
        REQUIRED_CONFIRMATIONS,
    ))
    .expect("original direct inclusion funding observation")
}

pub fn assert_funding_response(response: &FundingResponse, initial_tip_height: u64) -> String {
    assert_eq!(response.schema_version, 1);
    assert_eq!(response.amount_zatoshi, AMOUNT_ZATOSHI);
    assert_eq!(response.confirmations, REQUIRED_CONFIRMATIONS);
    assert_eq!(response.pool, "ironwood");
    assert!(response.mined_height > initial_tip_height);
    assert_eq!(
        response.final_tip_height,
        response
            .mined_height
            .checked_add(u64::from(REQUIRED_CONFIRMATIONS - 1))
            .expect("funding confirmation height overflow")
    );
    assert_eq!(response.txid_hex.len(), 64);
    assert!(response
        .txid_hex
        .bytes()
        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)));
    history_txid_from_rpc(&response.txid_hex)
}

pub fn history_txid_from_rpc(txid: &str) -> String {
    let mut bytes = hex::decode(txid).expect("RPC transaction id");
    assert_eq!(bytes.len(), 32);
    bytes.reverse();
    hex::encode(bytes)
}

pub fn path_string(path: &Path) -> String {
    crate::common::path_str(path)
}
