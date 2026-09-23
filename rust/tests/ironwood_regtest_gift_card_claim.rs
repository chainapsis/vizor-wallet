//! Gift Card claims on the Dockerized Ironwood regtest stack
//! (`scripts/ironwood-regtest`). Each test resets the chain.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

use rust_lib_zcash_wallet::api::{simple as simple_api, sync as sync_api, wallet as wallet_api};
use tempfile::TempDir;

const NETWORK: &str = "regtest";
const FUNDER_MNEMONIC: &str = "winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used";
const GIFT_ZATOSHI: u64 = 50_000_000;
const CLAIM_FEE_RESERVE_ZATOSHI: u64 = 10_000;
const CLAIM_CONFIRMATIONS: u32 = 2;
const ORDINARY_UNTRUSTED_CONFIRMATIONS: u32 = 6;

static STACK: Mutex<()> = Mutex::new(());

struct Wallet {
    _dir: TempDir,
    db: String,
    account: String,
    address: String,
}

/// A claim at two confirmations survives a one-block reorg, and only the
/// claim that discards its OVK hides the recipient from the link's seed.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn gift_card_claims_at_two_confirmations_and_discards_the_card_ovk() {
    let _guard = STACK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    start_post_activation_chain();

    // One pre-activation Orchard note per funder, so both cards can be funded
    // in the same block without waiting for change.
    let second_funder_mnemonic = wallet_api::generate_mnemonic();
    let funder = import("Funder", FUNDER_MNEMONIC, 1);
    let second_funder = import("Second funder", &second_funder_mnemonic, 1);
    let destinations = serde_json::json!([funder.address, second_funder.address]).to_string();
    run_harness("fund-orchard.sh", &[&destinations, "2.0", "10", "1", "2"]);
    run_harness("activate-ironwood.sh", &[]);
    mine(ORDINARY_UNTRUSTED_CONFIRMATIONS);
    sync(&funder.db);
    sync(&second_funder.db);

    let recipient = import(
        "Recipient",
        &wallet_api::generate_mnemonic(),
        latest_height(),
    );
    let discard_card_mnemonic = wallet_api::generate_mnemonic();
    let sender_card_mnemonic = wallet_api::generate_mnemonic();
    let card_birthday = latest_height();
    let discard_card = import("Discard card", &discard_card_mnemonic, card_birthday);
    let sender_card = import("Sender card", &sender_card_mnemonic, card_birthday);

    fund_card(&funder, FUNDER_MNEMONIC, &discard_card, "fund-discard");
    fund_card(
        &second_funder,
        &second_funder_mnemonic,
        &sender_card,
        "fund-sender",
    );
    mine(1);

    // One confirmation is not enough for the claim policy.
    claim_sync(&discard_card);
    assert!(
        claimable(&discard_card, &recipient) < GIFT_ZATOSHI,
        "a card must not be claimable after one confirmation"
    );

    mine(CLAIM_CONFIRMATIONS - 1);
    claim_sync(&discard_card);
    assert!(claimable(&discard_card, &recipient) >= GIFT_ZATOSHI);
    assert!(
        ordinary_claimable(&discard_card, &recipient) < GIFT_ZATOSHI,
        "the ordinary six-confirmation policy must still refuse this note"
    );

    let claim = sync_api::propose_payment_link_claim(
        discard_card.db.clone(),
        NETWORK.into(),
        discard_card.account.clone(),
        "claim-discard".into(),
        recipient.address.clone(),
        GIFT_ZATOSHI,
    )
    .expect("propose claim at two confirmations");
    let claim_result = execute(
        &discard_card,
        &discard_card_mnemonic,
        claim.proposal_id,
        "claim-discard",
    );
    assert_eq!(
        claim_result.status, "broadcasted",
        "{:?}",
        claim_result.message
    );

    // Replace the tip block. The claim's anchor is one block below the old tip,
    // so the reorg cannot invalidate it.
    let tip = latest_height();
    let reorg = run_harness("reorg.sh", &[&(tip - 1).to_string()]);
    let held = held_txids(&reorg);
    assert!(
        held.iter()
            .any(|txid| claim_result.txids.split(',').any(|id| id == txid)),
        "the claim must be held in the mempool across the reorg: {reorg}"
    );
    let mut release_args: Vec<&str> = held.iter().map(String::as_str).collect();
    release_args.sort_unstable();
    run_harness("release-reorg-transactions.sh", &release_args);
    mine(1);

    sync(&recipient.db);
    let received = sync_api::get_balance(
        recipient.db.clone(),
        NETWORK.into(),
        recipient.account.clone(),
    )
    .expect("recipient balance");
    assert_eq!(
        received.total, GIFT_ZATOSHI,
        "the claim must be mined after the one-block reorg"
    );

    // Control group: an ordinary send from the other card keeps the sender OVK.
    mine(ORDINARY_UNTRUSTED_CONFIRMATIONS);
    claim_sync(&sender_card);
    let control = sync_api::propose_send(
        sender_card.db.clone(),
        NETWORK.into(),
        sender_card.account.clone(),
        "claim-sender".into(),
        recipient.address.clone(),
        GIFT_ZATOSHI,
        None,
    )
    .expect("propose ordinary control send");
    let control_result = execute(
        &sender_card,
        &sender_card_mnemonic,
        control.proposal_id,
        "claim-sender",
    );
    assert_eq!(
        control_result.status, "broadcasted",
        "{:?}",
        control_result.message
    );
    mine(1);

    // A separate full-sync wallet restored from each link's seed.
    let discard_view = link_holder_view_of_spend(&discard_card_mnemonic, card_birthday);
    let sender_view = link_holder_view_of_spend(&sender_card_mnemonic, card_birthday);
    assert_eq!(sender_view.tx_kind, "sent", "control: {sender_view:?}");
    assert!(
        sender_view
            .outputs
            .iter()
            .any(|output| output.address.is_some() && output.amount_zatoshi == GIFT_ZATOSHI),
        "control: the sender OVK must recover the recipient output: {sender_view:?}"
    );
    // Without a recoverable output the spend cannot even be classified as a
    // send; the link holder sees only that the card's note was spent.
    assert_ne!(discard_view.tx_kind, "sent", "{discard_view:?}");
    assert!(
        discard_view
            .outputs
            .iter()
            .all(|output| output.address.is_none() || output.amount_zatoshi != GIFT_ZATOSHI),
        "the claim must not reveal the recipient to the link's seed: {discard_view:?}"
    );
}

#[derive(Debug)]
struct LinkHolderView {
    tx_kind: String,
    outputs: Vec<RecoveredOutput>,
}

#[derive(Debug)]
struct RecoveredOutput {
    address: Option<String>,
    amount_zatoshi: u64,
}

fn link_holder_view_of_spend(mnemonic: &str, birthday: u64) -> LinkHolderView {
    let observer = import("Link holder", mnemonic, birthday);
    sync(&observer.db);
    let history = sync_api::get_transaction_history(
        observer.db.clone(),
        NETWORK.into(),
        None,
        observer.account.clone(),
    )
    .expect("observer history");
    let spends: Vec<_> = history
        .iter()
        .filter(|tx| tx.account_balance_delta < 0)
        .collect();
    assert_eq!(
        spends.len(),
        1,
        "the link holder must see the card's note spent once: {:?}",
        history
            .iter()
            .map(|tx| (&tx.tx_kind, tx.account_balance_delta))
            .collect::<Vec<_>>()
    );
    let detail = sync_api::get_transaction_detail(
        observer.db.clone(),
        NETWORK.into(),
        observer.account.clone(),
        spends[0].txid_hex.clone(),
        spends[0].tx_kind.clone(),
    )
    .expect("observer transaction detail");
    LinkHolderView {
        tx_kind: spends[0].tx_kind.clone(),
        outputs: detail
            .outputs
            .into_iter()
            .map(|output| RecoveredOutput {
                address: output.address,
                amount_zatoshi: output.amount_zatoshi,
            })
            .collect(),
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

fn fund_card(funder: &Wallet, funder_mnemonic: &str, card: &Wallet, flow: &str) {
    let proposal = sync_api::propose_send(
        funder.db.clone(),
        NETWORK.into(),
        funder.account.clone(),
        flow.into(),
        card.address.clone(),
        GIFT_ZATOSHI + CLAIM_FEE_RESERVE_ZATOSHI,
        None,
    )
    .expect("propose card funding");
    let result = execute(funder, funder_mnemonic, proposal.proposal_id, flow);
    assert_eq!(result.status, "broadcasted", "{:?}", result.message);
}

fn execute(
    wallet: &Wallet,
    mnemonic: &str,
    proposal_id: u64,
    flow: &str,
) -> sync_api::ExecuteProposalResult {
    sync_api::execute_proposal(
        wallet.db.clone(),
        lightwalletd_url(),
        proposal_id,
        flow.into(),
        mnemonic.as_bytes().to_vec(),
        None,
        None,
    )
    .expect("execute proposal")
}

fn claimable(card: &Wallet, recipient: &Wallet) -> u64 {
    zero_when_insufficient(sync_api::estimate_payment_link_claim_max(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        recipient.address.clone(),
    ))
}

fn ordinary_claimable(card: &Wallet, recipient: &Wallet) -> u64 {
    zero_when_insufficient(sync_api::estimate_send_max(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        recipient.address.clone(),
        None,
    ))
}

fn zero_when_insufficient(result: Result<sync_api::SendMaxEstimateResult, String>) -> u64 {
    match result {
        Ok(estimate) => estimate.amount_zatoshi,
        Err(error) if error.to_lowercase().contains("insufficient") => 0,
        Err(error) => panic!("estimate claim: {error}"),
    }
}

fn claim_sync(card: &Wallet) {
    sync_api::run_payment_link_claim_sync(
        format!("claim-{}", card.account),
        card.db.clone(),
        lightwalletd_url(),
        NETWORK.into(),
        false,
    )
    .expect("claim sync");
}

fn sync(db: &str) {
    sync_api::run_full_sync_blocking(db.to_string(), lightwalletd_url(), NETWORK.into(), 1)
        .expect("sync wallet");
}

fn mine(blocks: u32) {
    run_harness("mine.sh", &[&blocks.to_string()]);
}

fn held_txids(reorg_json: &str) -> Vec<String> {
    let value: serde_json::Value =
        serde_json::from_str(reorg_json.lines().last().unwrap_or_default())
            .unwrap_or_else(|error| panic!("parse reorg output {reorg_json}: {error}"));
    value["heldTxids"]
        .as_array()
        .expect("heldTxids")
        .iter()
        .map(|txid| txid.as_str().expect("txid").to_string())
        .collect()
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
