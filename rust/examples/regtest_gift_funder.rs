//! Host-only Gift E2E faucet. Uses the wallet's Ironwood transaction builder,
//! in a separate process from the recipient app's sync and secure storage.
use rust_lib_zcash_wallet::api::{simple, sync, wallet};
use serde_json::json;
use std::path::Path;

const NETWORK: &str = "regtest";
// Public regtest fixture; never use this seed outside the disposable local chain.
const MNEMONIC: &str = "winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used";

fn run(args: &[String]) -> Result<serde_json::Value, String> {
    match args {
        [command, db] if command == "prepare" => {
            if Path::new(db).exists() {
                return Err("Funder DB already exists; reset the Gift E2E chain first".into());
            }
            let account = wallet::import_wallet(
                MNEMONIC.into(), String::new(), Some(1), NETWORK.into(),
                db.clone(), Some("Gift E2E funder".into()),
            )?;
            sync::update_chain_tip(db.clone(), NETWORK.into(), 1)?;
            let mut addresses = vec![account.unified_address];
            // Three independently spendable notes: one per native scenario.
            for _ in 1..3 {
                addresses.push(sync::get_next_available_address(
                    db.clone(), NETWORK.into(), account.account_uuid.clone(), "orchard".into(),
                )?);
            }
            Ok(json!({"addresses": addresses}))
        }
        [command, db, activation, url, destination, amount] if command == "fund" => {
            let activation = activation.parse::<u32>().map_err(|e| e.to_string())?;
            let amount = amount.parse::<u64>().map_err(|e| e.to_string())?;
            if amount == 0 || !Path::new(db).is_file() {
                return Err("Funding requires a prepared DB and positive amount".into());
            }
            simple::configure_regtest_ironwood_activation_height(activation)?;
            let tip = wallet::get_latest_block_height(url.clone(), NETWORK.into())?;
            if tip < u64::from(activation) {
                return Err("Gift funding requires an active Ironwood chain".into());
            }
            sync::run_full_sync_blocking(db.clone(), url.clone(), NETWORK.into(), 1)?;
            let accounts = wallet::list_accounts(db.clone(), NETWORK.into())?;
            if accounts.len() != 1 {
                return Err("Gift E2E funder requires exactly one account".into());
            }
            let flow = "gift-e2e-funding".to_string();
            let proposal = sync::propose_send(
                db.clone(), NETWORK.into(), accounts[0].uuid.clone(), flow.clone(),
                destination.clone(), amount, None,
            )?;
            let result = sync::execute_proposal(
                db.clone(), url.clone(), proposal.proposal_id, flow,
                MNEMONIC.as_bytes().to_vec(), None, None,
            )?;
            if result.status != "broadcasted" || result.broadcasted_count != result.total_count {
                return Err(format!("Gift funding did not fully broadcast: {} {:?}", result.status, result.message));
            }
            Ok(json!({"txids": result.txids}))
        }
        _ => Err("Usage: regtest_gift_funder prepare <db> | fund <db> <activation> <lightwalletd-url> <address> <zatoshi>".into()),
    }
}

fn main() {
    match run(&std::env::args().skip(1).collect::<Vec<_>>()) {
        Ok(result) => println!("{result}"),
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}
