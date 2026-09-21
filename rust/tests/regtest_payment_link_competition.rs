mod common;

use common::*;
use rust_lib_zcash_wallet::api::sync as api;
use std::path::Path;

fn claim(
    db: &Path,
    account: &str,
    mnemonic: &str,
    destination: &str,
    flow: &str,
) -> api::ExecuteProposalResult {
    let proposal = api::propose_send(
        path_str(db),
        REGTEST_NETWORK.into(),
        account.into(),
        flow.into(),
        destination.into(),
        50_000_000,
        None,
    )
    .unwrap();
    let params = proposal
        .needs_sapling_params
        .then(|| sapling_params().expect("Sapling params"));
    api::execute_proposal(
        path_str(db),
        LIGHTWALLETD_URL.into(),
        proposal.proposal_id,
        flow.into(),
        mnemonic.as_bytes().to_vec(),
        params.as_ref().map(|p| p.spend_path.clone()),
        params.as_ref().map(|p| p.output_path.clone()),
    )
    .unwrap()
}

/// Both claim wallets scan the same funding before either competitor submits.
/// The loser must retain evidence of its own transaction, distinguish the
/// winner, and exclude the losing spend from subsequent recovery broadcasts.
#[test]
#[ignore = "requires explicitly requested Docker regtest execution"]
fn one_card_two_claimants_preserve_and_resolve_losing_transaction() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();
    let (a_dir, card) = create_wallet("Card A");
    let (b_dir, b_card) = import_wallet_with_birthday(&card.mnemonic, "Card B", Some(1));
    let a_db = a_dir.path().join("zcash_wallet.db");
    let b_db = b_dir.path().join("zcash_wallet.db");
    let (winner_dir, winner) = create_wallet("Winner");
    let (loser_dir, loser) = create_wallet("Loser");
    fund_wallet(&card.unified_address, "0.5001");
    sync_wallet(&a_db);
    sync_wallet(&b_db);
    let a = claim(
        &a_db,
        &card.account_uuid,
        &card.mnemonic,
        &winner.unified_address,
        "card-a",
    );
    assert_eq!(a.status, "broadcasted");
    let b = claim(
        &b_db,
        &b_card.account_uuid,
        &card.mnemonic,
        &loser.unified_address,
        "card-b",
    );
    assert_ne!(b.status, "broadcasted");
    assert_eq!(b.broadcast_failure_kind.as_deref(), Some("rejected"));
    // Wire IDs use display order; the evidence API uses storage/protocol order.
    let b_ids = b
        .txids
        .split(',')
        .map(|id| {
            let mut bytes = hex::decode(id).unwrap();
            bytes.reverse();
            hex::encode(bytes)
        })
        .collect::<Vec<_>>();
    mine_blocks(6);
    api::run_payment_link_claim_sync(
        "loser-read-only".into(),
        path_str(&b_db),
        LIGHTWALLETD_URL.into(),
        REGTEST_NETWORK.into(),
        false,
    )
    .unwrap();
    let evidence = api::get_payment_link_spend_evidence(
        path_str(&b_db),
        b_card.account_uuid.clone(),
        b_ids.join(","),
    )
    .unwrap();
    assert!(evidence.all_funds_spent_elsewhere);
    assert!(b_ids
        .iter()
        .all(|id| evidence.conflicted_txids.contains(id)));
    // Reopening the API proves that no in-memory submission outcome is needed.
    let reopened =
        api::get_payment_link_spend_evidence(path_str(&b_db), b_card.account_uuid, b_ids.join(","))
            .unwrap();
    assert_eq!(reopened.conflicted_txids, evidence.conflicted_txids);
    sync_wallet(&winner_dir.path().join("zcash_wallet.db"));
    sync_wallet(&loser_dir.path().join("zcash_wallet.db"));
    assert_eq!(
        get_balance(
            &winner_dir.path().join("zcash_wallet.db"),
            &winner.account_uuid
        )
        .total,
        50_000_000
    );
    assert_eq!(
        get_balance(
            &loser_dir.path().join("zcash_wallet.db"),
            &loser.account_uuid
        )
        .total,
        0
    );
}
