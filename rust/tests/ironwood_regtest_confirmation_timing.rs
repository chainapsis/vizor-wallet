//! When sent funds become spendable again, on the Dockerized Ironwood regtest
//! stack (`scripts/ironwood-regtest`). The test resets the chain.

use std::path::{Path, PathBuf};
use std::process::Command;

use rust_lib_zcash_wallet::api::{simple as simple_api, sync as sync_api, wallet as wallet_api};
use tempfile::TempDir;

const NETWORK: &str = "regtest";
const SENDER_MNEMONIC: &str = "winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used";
const FUNDING_ZEC: &str = "2.0";
const FUNDING_ZATOSHI: u64 = 200_000_000;
const SEND_ZATOSHI: u64 = 50_000_000;
const CHANGE_CONFIRMATIONS: u32 = 3;
const RECEIVED_CONFIRMATIONS: u32 = 6;

struct Wallet {
    _dir: TempDir,
    db: String,
    account: String,
    address: String,
}

/// The confirmation counts are what a user waits, with the block that mines
/// the send as the first. They hold only while the SDK's anchor reaches a note
/// on its last required confirmation, which unit tests cannot observe.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn change_is_spendable_at_three_confirmations_and_received_funds_at_six() {
    start_post_activation_chain();

    // One note, aged past every policy, so the send leaves only its change.
    let sender = import("Sender", SENDER_MNEMONIC, 1);
    run_harness(
        "fund-orchard.sh",
        &[&sender.address, FUNDING_ZEC, "10", "1", "1"],
    );
    run_harness("activate-ironwood.sh", &[]);
    mine(10);
    sync(&sender.db);
    assert_eq!(balance(&sender).spendable, FUNDING_ZATOSHI);
    let recipient = import(
        "Recipient",
        &wallet_api::generate_mnemonic(),
        latest_height(),
    );
    let other = import("Other", &wallet_api::generate_mnemonic(), latest_height());

    let proposal = sync_api::propose_send(
        sender.db.clone(),
        NETWORK.into(),
        sender.account.clone(),
        "confirmation-timing".into(),
        recipient.address.clone(),
        SEND_ZATOSHI,
        None,
    )
    .expect("propose send");
    let change = FUNDING_ZATOSHI - SEND_ZATOSHI - proposal.fee_zatoshi;
    let result = sync_api::execute_proposal(
        sender.db.clone(),
        lightwalletd_url(),
        proposal.proposal_id,
        "confirmation-timing".into(),
        SENDER_MNEMONIC.as_bytes().to_vec(),
        None,
        None,
    )
    .expect("execute send");
    assert_eq!(result.status, "broadcasted", "{:?}", result.message);

    for confirmations in 1..=RECEIVED_CONFIRMATIONS {
        mine(1);
        sync(&sender.db);
        sync(&recipient.db);

        let expected_change = if confirmations >= CHANGE_CONFIRMATIONS {
            change
        } else {
            0
        };
        assert_eq!(
            balance(&sender).spendable,
            expected_change,
            "change at {confirmations} confirmation(s)"
        );
        assert_eq!(
            can_send(&sender, &other),
            confirmations >= CHANGE_CONFIRMATIONS,
            "sending change at {confirmations} confirmation(s)"
        );

        let expected_received = if confirmations >= RECEIVED_CONFIRMATIONS {
            SEND_ZATOSHI
        } else {
            0
        };
        assert_eq!(
            balance(&recipient).spendable,
            expected_received,
            "received funds at {confirmations} confirmation(s)"
        );
        assert_eq!(
            can_send(&recipient, &other),
            confirmations >= RECEIVED_CONFIRMATIONS,
            "sending received funds at {confirmations} confirmation(s)"
        );
    }
}

fn balance(wallet: &Wallet) -> sync_api::WalletBalance {
    sync_api::get_balance(wallet.db.clone(), NETWORK.into(), wallet.account.clone())
        .expect("get balance")
}

/// Whether the send path, not only the balance, treats the funds as spendable.
fn can_send(from: &Wallet, to: &Wallet) -> bool {
    match sync_api::estimate_send_max(
        from.db.clone(),
        NETWORK.into(),
        from.account.clone(),
        to.address.clone(),
        None,
    ) {
        Ok(estimate) => estimate.amount_zatoshi > 0,
        Err(error) if error.to_lowercase().contains("insufficient") => false,
        Err(error) => panic!("estimate send max: {error}"),
    }
}

fn start_post_activation_chain() {
    simple_api::configure_regtest_ironwood_activation_height(activation_height())
        .expect("configure wallet NU6.3 activation");
    run_harness("reset.sh", &[]);
    run_harness("up.sh", &[]);
}

fn import(name: &str, mnemonic: &str, birthday: u64) -> Wallet {
    let dir = tempfile::tempdir().expect("wallet tempdir");
    let db = path_string(&dir.path().join("zcash_wallet.db"));
    let wallet = wallet_api::import_wallet(
        mnemonic.to_string(),
        String::new(),
        Some(birthday),
        NETWORK.into(),
        db.clone(),
        Some(name.to_string()),
    )
    .unwrap_or_else(|error| panic!("import {name}: {error}"));
    Wallet {
        _dir: dir,
        db,
        account: wallet.account_uuid,
        address: wallet.unified_address,
    }
}

fn sync(db: &str) {
    sync_api::run_full_sync_blocking(db.to_string(), lightwalletd_url(), NETWORK.into(), 1)
        .expect("sync wallet");
}

fn mine(blocks: u32) {
    run_harness("mine.sh", &[&blocks.to_string()]);
}

fn latest_height() -> u64 {
    wallet_api::get_latest_block_height(lightwalletd_url(), NETWORK.into())
        .expect("read Ironwood regtest tip")
}

fn activation_height() -> u32 {
    std::env::var("IRONWOOD_ACTIVATION_HEIGHT")
        .unwrap_or_else(|_| "500".to_string())
        .parse()
        .expect("IRONWOOD_ACTIVATION_HEIGHT must be a u32")
}

fn lightwalletd_url() -> String {
    let port = std::env::var("IRONWOOD_LIGHTWALLETD_PORT").unwrap_or_else(|_| "19067".to_string());
    format!("http://127.0.0.1:{port}")
}

fn run_harness(script: &str, args: &[&str]) -> String {
    let path = repo_root()
        .join("scripts")
        .join("ironwood-regtest")
        .join(script);
    let output = Command::new(path)
        .args(args)
        .current_dir(repo_root())
        .env(
            "IRONWOOD_ACTIVATION_HEIGHT",
            activation_height().to_string(),
        )
        .output()
        .unwrap_or_else(|error| panic!("run {script}: {error}"));
    assert!(
        output.status.success(),
        "{script} failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("rust crate must be inside the repository")
        .to_path_buf()
}

fn path_string(path: &Path) -> String {
    path.to_str().expect("UTF-8 path").to_string()
}
