//! Explicitly invoked against an isolated regtest stack; never resets a stack.
use std::{process::Command, time::Instant};

use rust_lib_zcash_wallet::api::{simple, sync, wallet};
use tempfile::TempDir;

const NETWORK: &str = "regtest";
const GIFT: u64 = 50_000_000;

#[test]
#[ignore = "creates an explicitly requested regtest fixture for the mobile walkthrough"]
fn create_mobile_event_fixture() {
    let output = std::env::var("VIZOR_DIRECT_GIFT_FIXTURE_OUTPUT").expect("fixture output path");
    let compose = std::env::var("VIZOR_DIRECT_GIFT_COMPOSE").expect("isolated compose file");
    simple::configure_regtest_ironwood_activation_height(500).unwrap();
    assert!(tip() > 500, "requires an Ironwood regtest chain");
    let funder = create_wallet("Mobile fixture funder", tip());
    let transparent = wallet::get_transparent_receive_address(
        funder.db.clone(),
        NETWORK.into(),
        Some(funder.account.clone()),
    )
    .unwrap();
    cli(&compose, &["sendtoaddress", &transparent, "1.25"]);
    mine(&compose, 10);
    sync_wallet(&funder);
    let result = sync::shield_transparent_balance(
        funder.db.clone(),
        backend(),
        NETWORK.into(),
        funder.account.clone(),
        funder.mnemonic.as_bytes().to_vec(),
    )
    .unwrap();
    assert_eq!(result.status, "broadcasted");
    mine(&compose, 10);
    sync_wallet(&funder);
    // Event cards use the protocol birthday locally, absent from the shared link.
    let card = create_wallet("Mobile event card", 1);
    let flow = "mobile-event-funding";
    let proposal = sync::propose_send(
        funder.db.clone(),
        NETWORK.into(),
        funder.account.clone(),
        flow.into(),
        card.address.clone(),
        GIFT + 10_000,
        None,
    )
    .unwrap();
    let funded = execute(&funder, proposal.proposal_id, flow, backend());
    assert_eq!(funded.status, "broadcasted");
    mine(&compose, 10);
    std::fs::write(
        output,
        serde_json::to_vec(&serde_json::json!({
            "network": NETWORK, "mnemonic": card.mnemonic, "birthdayHeight": card.birthday,
            "amountZatoshi": GIFT.to_string(), "fundingTxid": funded.txids
        }))
        .unwrap(),
    )
    .unwrap();
}

struct Wallet {
    _dir: TempDir,
    db: String,
    account: String,
    address: String,
    mnemonic: String,
    birthday: u64,
}

#[test]
#[ignore = "requires explicitly configured isolated regtest and RPC-counting proxy"]
fn known_funding_block_claims_without_scanning_the_historical_gap() {
    let compose = std::env::var("VIZOR_DIRECT_GIFT_COMPOSE").expect("isolated compose file");
    assert!(std::path::Path::new(&compose).is_file());
    simple::configure_regtest_ironwood_activation_height(500).unwrap();
    if std::env::var_os("VIZOR_DIRECT_GIFT_REUSE_CHAIN").is_some() {
        assert!(
            tip() > 500,
            "reuse lane needs an Ironwood-active isolated chain"
        );
        let funder = create_wallet("Funder", tip());
        let transparent = wallet::get_transparent_receive_address(
            funder.db.clone(),
            NETWORK.into(),
            Some(funder.account.clone()),
        )
        .unwrap();
        cli(&compose, &["sendtoaddress", &transparent, "1.25"]);
        mine(&compose, 10);
        sync_wallet(&funder);
        let shielded = sync::shield_transparent_balance(
            funder.db.clone(),
            backend(),
            NETWORK.into(),
            funder.account.clone(),
            funder.mnemonic.as_bytes().to_vec(),
        )
        .unwrap();
        assert_eq!(shielded.status, "broadcasted");
        mine(&compose, 10);
        sync_wallet(&funder);
        run_card(&funder, "Ironwood", 200, &compose);
        exercise_recovery(&funder, &compose);
        exercise_expiry(&funder, &compose);
        return;
    }
    assert!(
        tip() < 200,
        "fresh lane needs a pre-Ironwood isolated chain"
    );
    // Mature node coinbase funds before using it as this test's faucet.
    if tip() < 110 {
        mine(&compose, 110 - tip());
    }
    let funder = create_wallet("Funder", tip());
    let transparent = wallet::get_transparent_receive_address(
        funder.db.clone(),
        NETWORK.into(),
        Some(funder.account.clone()),
    )
    .unwrap();
    cli(&compose, &["sendtoaddress", &transparent, "3.5"]);
    mine(&compose, 10);
    sync_wallet(&funder);
    let shielded = sync::shield_transparent_balance(
        funder.db.clone(),
        backend(),
        NETWORK.into(),
        funder.account.clone(),
        funder.mnemonic.as_bytes().to_vec(),
    )
    .unwrap();
    assert_eq!(shielded.status, "broadcasted");
    mine(&compose, 10);
    sync_wallet(&funder);

    // Existing Orchard pool, with no prior scan of the card's funding block.
    run_card(&funder, "Orchard", 200, &compose);

    let height = tip();
    if height < 506 {
        mine(&compose, 506 - height);
    }
    sync_wallet(&funder);
    // Ironwood pool, with 5,000 blocks between funding and claiming.
    run_card(&funder, "Ironwood", 5_000, &compose);
    exercise_recovery(&funder, &compose);
    exercise_expiry(&funder, &compose);
}

fn run_card(funder: &Wallet, pool: &str, gap: u64, compose: &str) {
    let card = create_wallet(pool, 1);
    let flow = format!("direct-gift-fund-{pool}");
    let proposal = sync::propose_send(
        funder.db.clone(),
        NETWORK.into(),
        funder.account.clone(),
        flow.clone(),
        card.address.clone(),
        GIFT + 10_000,
        None,
    )
    .expect("funding proposal");
    let funding = execute(funder, proposal.proposal_id, &flow, backend());
    assert_eq!(funding.status, "broadcasted", "{:?}", funding.message);
    assert_eq!(
        funding.txids.split(',').count(),
        1,
        "fixture needs a single funding transaction"
    );
    mine(compose, 2);
    sync_wallet(funder);
    // Change this pool's commitment root between funding and claiming. An
    // empty historical gap alone would leave the old anchor equal to the tip.
    let unrelated = create_wallet("Unrelated", tip());
    let noise_flow = format!("direct-gift-tree-change-{pool}");
    let noise_proposal = sync::propose_send(
        funder.db.clone(),
        NETWORK.into(),
        funder.account.clone(),
        noise_flow.clone(),
        unrelated.address.clone(),
        1_000_000,
        None,
    )
    .unwrap();
    let noise = execute(funder, noise_proposal.proposal_id, &noise_flow, backend());
    assert_eq!(noise.status, "broadcasted");
    mine(compose, gap + 2);
    let recipient = create_wallet("Recipient", tip());

    telemetry("reset");
    let start = Instant::now();
    sync::run_payment_link_claim_sync(
        format!("direct-{pool}"),
        card.db.clone(),
        proxy(),
        NETWORK.into(),
        false,
        Some(funding.txids.clone()),
    )
    .expect("direct preparation");
    let preparation_ms = start.elapsed().as_millis();
    let preparation_calls = telemetry("snapshot");
    let conn = rusqlite::Connection::open(&card.db).unwrap();
    let scanned: u64 = conn
        .query_row("SELECT COUNT(*) FROM blocks", [], |r| r.get(0))
        .unwrap();
    assert_eq!(scanned, 1, "the card must process only its funding block");
    let pending: bool = conn.query_row("SELECT EXISTS(SELECT 1 FROM scan_queue WHERE priority > 10 AND block_range_end - block_range_start > 100)", [], |r| r.get(0)).unwrap();
    assert!(pending, "the historical gap must remain unscanned");
    let (funding_height, prepared_tip): (u64, u64) = conn
        .query_row(
            "SELECT funding_height, tip_height FROM vizor_gift_direct_claim WHERE id=1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    drop(conn);
    let duplicate = copy_wallet(&card);
    let quote = sync::estimate_payment_link_claim_max(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        recipient.address.clone(),
    )
    .expect("real claim estimate");
    assert_eq!(quote.amount_zatoshi, GIFT);
    assert_eq!(quote.fee_zatoshi, 10_000);
    let claim_flow = format!("direct-gift-claim-{pool}");
    let proposal = sync::propose_payment_link_claim(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        claim_flow.clone(),
        recipient.address.clone(),
        GIFT,
    )
    .expect("real claim proposal");
    let start = Instant::now();
    let claimed = execute(&card, proposal.proposal_id, &claim_flow, proxy());
    let proof_and_broadcast_ms = start.elapsed().as_millis();
    assert_eq!(claimed.status, "broadcasted", "{:?}", claimed.message);
    assert_eq!(claimed.broadcasted_count, 1);
    let claim_calls = telemetry("snapshot");
    let mempool = cli(compose, &["getrawmempool"]);
    assert!(
        mempool.contains(&claimed.txids),
        "node must accept the actual claim"
    );
    let claimed_tx: serde_json::Value =
        serde_json::from_str(&cli(compose, &["getrawtransaction", &claimed.txids, "1"])).unwrap();
    let pool_key = pool.to_ascii_lowercase();
    let funding_tree: serde_json::Value = serde_json::from_str(&cli(
        compose,
        &["z_gettreestate", &funding_height.to_string()],
    ))
    .unwrap();
    let tip_tree: serde_json::Value = serde_json::from_str(&cli(
        compose,
        &["z_gettreestate", &prepared_tip.to_string()],
    ))
    .unwrap();
    let old_root = &funding_tree[&pool_key]["commitments"]["finalRoot"];
    let tip_root = &tip_tree[&pool_key]["commitments"]["finalRoot"];
    assert!(old_root.is_string() && tip_root.is_string());
    assert_ne!(old_root, tip_root, "fixture must change the pool root");
    assert_eq!(
        &claimed_tx[&pool_key]["anchor"], old_root,
        "claim must use its funding-block anchor"
    );
    assert!(!claimed_tx[&pool_key]["actions"]
        .as_array()
        .unwrap()
        .is_empty());
    mine(compose, 10);
    sync_wallet(&recipient);
    let balance = sync::get_balance(
        recipient.db.clone(),
        NETWORK.into(),
        recipient.account.clone(),
    )
    .unwrap();
    assert_eq!(balance.total, GIFT, "recipient must receive actual funds");
    let history = sync::get_transaction_history(
        recipient.db.clone(),
        NETWORK.into(),
        None,
        recipient.account.clone(),
    )
    .unwrap();
    assert!(
        history
            .iter()
            .any(|tx| zcash_primitives::transaction::TxId::from_bytes(
                hex::decode(&tx.txid_hex).unwrap().try_into().unwrap()
            )
            .to_string()
                == claimed.txids
                && tx.account_balance_delta == GIFT as i64
                && tx.mined_height > 0),
        "recipient must record the mined claim"
    );
    let conn = rusqlite::Connection::open(&card.db).unwrap();
    let scanned_after: u64 = conn
        .query_row("SELECT COUNT(*) FROM blocks", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        scanned_after, 1,
        "transaction construction must not scan the gap"
    );
    println!(
        "DIRECT_GIFT_RESULT {}",
        serde_json::json!({"pool":pool,"requested_funding_gap_blocks":gap,"birthday_height":card.birthday,"funding_height":funding_height,"prepared_tip":prepared_tip,"funding_age_blocks":prepared_tip-funding_height,"historical_span_blocks":prepared_tip-card.birthday,"funding_anchor_differs_from_tip":old_root!=tip_root,"processed_card_blocks":scanned_after,"preparation_ms":preparation_ms,"proof_and_broadcast_ms":proof_and_broadcast_ms,"recipient_received_zatoshi":balance.total,"preparation_rpc":preparation_calls,"prepare_and_claim_rpc":claim_calls})
    );
    // Reopening the original DB observes our mined spend, even without a full scan.
    prepare(&card, &funding.txids, false);
    assert!(sync::estimate_payment_link_claim_max(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        recipient.address.clone()
    )
    .is_err());

    // Another app holding the same printed link cannot receive the funds twice.
    let duplicate_flow = format!("duplicate-{pool}");
    let proposal = sync::propose_payment_link_claim(
        duplicate.db.clone(),
        NETWORK.into(),
        duplicate.account.clone(),
        duplicate_flow.clone(),
        unrelated.address.clone(),
        GIFT,
    )
    .unwrap();
    let rejected = execute(&duplicate, proposal.proposal_id, &duplicate_flow, proxy());
    assert_ne!(rejected.status, "broadcasted");
    assert_eq!(rejected.broadcast_failure_kind.as_deref(), Some("rejected"));
    println!("DIRECT_GIFT_DUPLICATE_REJECTED {pool}");
}

fn copy_wallet(source: &Wallet) -> Wallet {
    let dir = tempfile::tempdir().unwrap();
    let db = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    rusqlite::Connection::open(&source.db)
        .unwrap()
        .execute("VACUUM INTO ?1", [&db])
        .unwrap();
    Wallet {
        _dir: dir,
        db,
        account: source.account.clone(),
        address: source.address.clone(),
        mnemonic: source.mnemonic.clone(),
        birthday: source.birthday,
    }
}

fn prepare(card: &Wallet, funding: &str, retry: bool) {
    sync::run_payment_link_claim_sync(
        format!("recover-{}", card.account),
        card.db.clone(),
        proxy(),
        NETWORK.into(),
        retry,
        Some(funding.into()),
    )
    .unwrap_or_else(|error| {
        let conn = rusqlite::Connection::open(&card.db).unwrap();
        for table in [
            "blocks",
            "sapling_tree_checkpoints",
            "orchard_tree_checkpoints",
            "ironwood_tree_checkpoints",
        ] {
            let column = if table == "blocks" {
                "height"
            } else {
                "checkpoint_id"
            };
            let mut stmt = conn
                .prepare(&format!("SELECT {column} FROM {table} ORDER BY {column}"))
                .unwrap();
            let values = stmt
                .query_map([], |row| row.get::<_, u32>(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            eprintln!("Direct preparation failure: {table}: {values:?}");
        }
        panic!("direct preparation failed: {error}");
    });
}

fn exercise_recovery(funder: &Wallet, compose: &str) {
    sync_wallet(funder);
    let card = create_wallet("Recovery card", 1);
    let recipient = create_wallet("Recovery recipient", tip());
    let flow = "recovery-funding";
    let proposal = sync::propose_send(
        funder.db.clone(),
        NETWORK.into(),
        funder.account.clone(),
        flow.into(),
        card.address.clone(),
        GIFT + 10_000,
        None,
    )
    .unwrap();
    let funding = execute(funder, proposal.proposal_id, flow, backend());
    assert_eq!(funding.status, "broadcasted");
    mine(compose, 2);
    prepare(&card, &funding.txids, false);
    let funding_height: u64 = rusqlite::Connection::open(&card.db)
        .unwrap()
        .query_row(
            "SELECT funding_height FROM vizor_gift_direct_claim",
            [],
            |r| r.get(0),
        )
        .unwrap();
    reorg(compose, funding_height);
    assert!(sync::run_payment_link_claim_sync(
        "funding-reorg".into(),
        card.db.clone(),
        proxy(),
        NETWORK.into(),
        false,
        Some(funding.txids.clone())
    )
    .is_err());
    assert_eq!(
        rusqlite::Connection::open(&card.db)
            .unwrap()
            .query_row("SELECT COUNT(*) FROM vizor_gift_direct_claim", [], |r| r
                .get::<_, u64>(0))
            .unwrap(),
        0
    );
    mine(compose, 3);
    prepare(&card, &funding.txids, false);
    let quote = sync::estimate_payment_link_claim_max(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        recipient.address.clone(),
    )
    .unwrap();
    assert_eq!(quote.amount_zatoshi, GIFT);
    println!("DIRECT_GIFT_FUNDING_REORG_RECOVERED");

    // Simulate losing connectivity after signing and durable transaction storage.
    telemetry("fail-next-submission");
    let flow = "interrupted-claim";
    let proposal = sync::propose_payment_link_claim(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        flow.into(),
        recipient.address.clone(),
        GIFT,
    )
    .unwrap();
    let pending = execute(&card, proposal.proposal_id, flow, proxy());
    assert_ne!(pending.status, "broadcasted");
    assert!(!pending.txids.is_empty());
    prepare(&card, &funding.txids, true);
    assert!(cli(compose, &["getrawmempool"]).contains(&pending.txids));
    mine(compose, 2);
    prepare(&card, &funding.txids, false);
    let mined: serde_json::Value =
        serde_json::from_str(&cli(compose, &["getrawtransaction", &pending.txids, "1"])).unwrap();
    let block_hash = mined["blockhash"].as_str().unwrap();
    let block: serde_json::Value =
        serde_json::from_str(&cli(compose, &["getblock", block_hash])).unwrap();
    reorg(compose, block["height"].as_u64().unwrap());
    prepare(&card, &funding.txids, true);
    let conn = rusqlite::Connection::open(&card.db).unwrap();
    let mined_count: u64 = conn
        .query_row(
            "SELECT COUNT(*) FROM transactions t WHERE mined_height IS NOT NULL
        AND EXISTS(SELECT 1 FROM sent_notes s WHERE s.transaction_id=t.id_tx)",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        mined_count, 0,
        "reorg must invalidate our old claim confirmation"
    );
    drop(conn);
    // Allow the normal recipient wallet's confirmation/verification window,
    // just as in the successful fresh-card case above.
    mine(compose, 10);
    prepare(&card, &funding.txids, false);
    sync_wallet(&recipient);
    assert_eq!(
        sync::get_balance(
            recipient.db.clone(),
            NETWORK.into(),
            recipient.account.clone()
        )
        .unwrap()
        .total,
        GIFT
    );
    assert!(sync::estimate_payment_link_claim_max(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        recipient.address.clone()
    )
    .is_err());
    println!(
        "DIRECT_GIFT_INTERRUPTED_AND_REORG_CLAIM_RECOVERED {}",
        pending.txids
    );
}

fn reorg(compose: &str, height: u64) {
    let hash = cli(compose, &["getblockhash", &height.to_string()]);
    cli(compose, &["invalidateblock", hash.trim()]);
    let expected = height - 1;
    for _ in 0..120 {
        if tip() == expected {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(250));
    }
    panic!("lightwalletd did not observe the reorg");
}

fn exercise_expiry(funder: &Wallet, compose: &str) {
    const AMOUNT: u64 = 10_000_000;
    sync_wallet(funder);
    let card = create_wallet("Expiry card", 1);
    let recipient = create_wallet("Expiry recipient", tip());
    let flow = "expiry-funding";
    let proposal = sync::propose_send(
        funder.db.clone(),
        NETWORK.into(),
        funder.account.clone(),
        flow.into(),
        card.address.clone(),
        AMOUNT + 10_000,
        None,
    )
    .unwrap();
    let funding = execute(funder, proposal.proposal_id, flow, backend());
    assert_eq!(funding.status, "broadcasted");
    mine(compose, 2);
    prepare(&card, &funding.txids, false);
    telemetry("fail-next-submission");
    let flow = "expired-claim";
    let proposal = sync::propose_payment_link_claim(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        flow.into(),
        recipient.address.clone(),
        AMOUNT,
    )
    .unwrap();
    let pending = execute(&card, proposal.proposal_id, flow, proxy());
    assert_ne!(pending.status, "broadcasted");
    let expiry: u64 = rusqlite::Connection::open(&card.db)
        .unwrap()
        .query_row(
            "SELECT MAX(expiry_height) FROM transactions t WHERE EXISTS
        (SELECT 1 FROM sent_notes s WHERE s.transaction_id=t.id_tx)",
            [],
            |r| r.get(0),
        )
        .unwrap();
    mine(compose, expiry - tip() + 2);
    prepare(&card, &funding.txids, false);
    let quote = sync::estimate_payment_link_claim_max(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        recipient.address.clone(),
    )
    .unwrap();
    assert_eq!(quote.amount_zatoshi, AMOUNT);
    let flow = "retry-expired-claim";
    let proposal = sync::propose_payment_link_claim(
        card.db.clone(),
        NETWORK.into(),
        card.account.clone(),
        flow.into(),
        recipient.address.clone(),
        AMOUNT,
    )
    .unwrap();
    let result = execute(&card, proposal.proposal_id, flow, proxy());
    assert_eq!(result.status, "broadcasted");
    assert_ne!(pending.txids, result.txids);
    mine(compose, 10);
    sync_wallet(&recipient);
    assert_eq!(
        sync::get_balance(
            recipient.db.clone(),
            NETWORK.into(),
            recipient.account.clone()
        )
        .unwrap()
        .total,
        AMOUNT
    );
    println!("DIRECT_GIFT_EXPIRED_CLAIM_RETRY_PASSED");
}

fn create_wallet(name: &str, birthday: u64) -> Wallet {
    let dir = tempfile::tempdir().unwrap();
    let db = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let created = wallet::create_wallet(
        NETWORK.into(),
        db.clone(),
        Some(birthday),
        Some(name.into()),
    )
    .unwrap();
    Wallet {
        _dir: dir,
        db,
        account: created.account_uuid,
        address: created.unified_address,
        mnemonic: created.mnemonic,
        birthday,
    }
}

fn execute(w: &Wallet, proposal: u64, flow: &str, url: String) -> sync::ExecuteProposalResult {
    sync::execute_proposal(
        w.db.clone(),
        url,
        proposal,
        flow.into(),
        w.mnemonic.as_bytes().to_vec(),
        None,
        None,
    )
    .expect("proof generation and real broadcast")
}
fn backend() -> String {
    "http://127.0.0.1:9267".into()
}
fn proxy() -> String {
    "http://127.0.0.1:9297".into()
}
fn sync_wallet(w: &Wallet) {
    sync::run_full_sync_blocking(w.db.clone(), backend(), NETWORK.into(), 1).unwrap();
}
fn tip() -> u64 {
    wallet::get_latest_block_height(backend(), NETWORK.into()).unwrap()
}
fn cli(compose: &str, args: &[&str]) -> String {
    let output = Command::new("docker")
        .args([
            "compose",
            "-f",
            compose,
            "-p",
            "vizor-gift-direct-claim-822",
            "exec",
            "-T",
            "zcashd",
            "zcash-cli",
            "-conf=/etc/zcash/zcash.conf",
            "-rpcclienttimeout=3600",
        ])
        .args(args)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "isolated node RPC: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap()
}
fn mine(compose: &str, count: u64) {
    cli(compose, &["generate", &count.to_string()]);
    let expected = cli(compose, &["getblockcount"])
        .trim()
        .parse::<u64>()
        .unwrap();
    for _ in 0..120 {
        if tip() >= expected {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(250));
    }
    panic!("lightwalletd did not catch up to the isolated node");
}
fn telemetry(path: &str) -> serde_json::Value {
    let output = Command::new("curl")
        .args([
            "--fail",
            "--silent",
            &format!("http://127.0.0.1:9298/{path}"),
        ])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "RPC-counting proxy must be running"
    );
    serde_json::from_slice(&output.stdout).unwrap()
}
