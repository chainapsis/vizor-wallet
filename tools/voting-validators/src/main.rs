//! Offline verifier for the scheduled updater. No wallet or network dependencies.
#[path = "../../../rust/src/wallet/voting/participation_evidence.rs"]
mod evidence;

use evidence::*;
use serde::Deserialize;
use serde_json::{json, Value};
use std::io::{self, Read};
use tendermint::trust_threshold::TrustThresholdFraction;
use tendermint_light_client_verifier::operations::voting_power::{
    ProdVotingPowerCalculator, VotingPowerCalculator,
};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    chain_id: String,
    trusted_hash: String,
    trusted_validators: Vec<tendermint::validator::Info>,
    commit: Envelope<CommitResult>,
    validators: Envelope<ValidatorsResult>,
    now: i64,
    #[serde(default)]
    keys: Vec<String>,
    #[serde(default)]
    queries: Vec<Envelope<QueryResult>>,
}

fn verify(request: Request) -> Result<Value, String> {
    let trusted = checked_validator_set(&ValidatorsResult {
        validators: request.trusted_validators,
    })?;
    if trusted.hash().to_string() != request.trusted_hash {
        return Err("Trusted validator data does not match its pin".into());
    }
    let current = checked_validator_set(&request.validators.result)?;
    let signed = &request.commit.result;
    verify_header_with_trust(signed, &current, &request.chain_id, &trusted, request.now)?;
    if request.keys.len() > 1024 || request.keys.len() != request.queries.len() {
        return Err(INVALID.into());
    }
    let h = &signed.signed_header.header;
    let height = h.height.value().checked_sub(1).ok_or(INVALID)?;
    let mut used = Vec::new();
    for (key, query) in request.keys.iter().zip(&request.queries) {
        let key = hex::decode(key).map_err(|_| INVALID)?;
        if key.len() != 66 || key[..2] != [1, 0] {
            return Err(INVALID.into());
        }
        used.push(verify_query(
            &query.result.response,
            &key,
            h.app_hash.as_bytes(),
            height,
        )?);
    }
    // A threshold of 1 cannot be exceeded, so the calculator visits and
    // verifies every block signature instead of stopping at the quorum.
    let all = TrustThresholdFraction::new(1, 1).unwrap();
    let calculator = ProdVotingPowerCalculator::default();
    let previous_power = calculator
        .voting_power_in(&signed.signed_header, &trusted, all)
        .map_err(|e| e.to_string())?;
    let current_power = calculator
        .voting_power_in(&signed.signed_header, &current, all)
        .map_err(|e| e.to_string())?;
    let validators: Vec<_> = current
        .validators()
        .iter()
        .map(|v| {
            json!({
                "address": v.address.to_string(), "pub_key": v.pub_key,
                "voting_power": v.power.value().to_string(), "proposer_priority": "0",
            })
        })
        .collect();
    Ok(json!({
        "validator_set_hash": current.hash().to_string(),
        "validators": validators,
        "height": h.height.value(),
        "header_time": h.time,
        "previous_power": previous_power,
        "current_power": current_power,
        "used": used,
    }))
}

fn run() -> Result<Value, String> {
    const LIMIT: u64 = 8 * 1024 * 1024;
    let mut input = Vec::new();
    io::stdin()
        .take(LIMIT + 1)
        .read_to_end(&mut input)
        .map_err(|e| e.to_string())?;
    if input.len() as u64 > LIMIT {
        return Err("Evidence exceeds size limit".into());
    }
    verify(serde_json::from_slice(&input).map_err(|e| e.to_string())?)
}

fn main() {
    match run() {
        Ok(value) => println!("{value}"),
        Err(error) => {
            eprintln!("Verification failed: {error}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Value {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../rust/tests/fixtures/voting-participation/main-20261102.json"
        ))
        .unwrap();
        let commit: Envelope<CommitResult> =
            serde_json::from_value(fixture["commit"].clone()).unwrap();
        let now = commit.result.signed_header.header.time.unix_timestamp();
        json!({
            "chain_id": "zvote-1", "trusted_hash": fixture["commit"]["result"]["signed_header"]["header"]["validators_hash"],
            "trusted_validators": fixture["validators"]["result"]["validators"],
            "commit": fixture["commit"], "validators": fixture["validators"],
            "keys": fixture["keys"], "queries": fixture["queries"], "now": now,
        })
    }

    #[test]
    fn authenticates_real_state_proofs_and_counts_all_signatures() {
        let result = verify(serde_json::from_value(fixture()).unwrap()).unwrap();
        assert_eq!(result["used"], json!([true, false]));
        assert_eq!(result["current_power"]["tallied"], 90);
    }

    #[test]
    fn rejects_untrusted_pins_networks_times_and_forged_proofs() {
        for (key, value) in [
            ("trusted_hash", json!("00".repeat(32))),
            ("chain_id", json!("svote-1")),
            ("now", json!(0)),
        ] {
            let mut request = fixture();
            request[key] = value;
            assert!(verify(serde_json::from_value(request).unwrap()).is_err());
        }
        let mut request = fixture();
        request["queries"][0]["result"]["response"]["proofOps"]["ops"][0]["data"] = json!("AA==");
        assert!(verify(serde_json::from_value(request).unwrap()).is_err());
    }
}
