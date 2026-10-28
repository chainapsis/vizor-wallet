use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::Command;

use rust_lib_zcash_wallet::api::{simple as simple_api, sync as sync_api, wallet as wallet_api};

const NETWORK: &str = "regtest";
const MIGRATION_MNEMONIC: &str = "winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used";
const PENDING_PASSWORD: &str = "nu7-regtest-password";
const PENDING_SALT_BASE64: &str = "AAECAwQFBgcICQoLDA0ODw==";
const COINBASE_MATURITY: u64 = 100;
const SEND_ZATOSHI: u64 = 1_000_000;
const PRE_NU7_EXPIRY_DELTA: u64 = 40;
const NU7_EXPIRY_DELTA: u64 = 120;
/// Early enough that preparation finishes and parts fall due before NU7 under
/// fast migration timing (delays of at most 48 blocks).
const RUN_START_BEFORE_NU7: u64 = 100;
const PRE_NU7_EXPIRY_MODULUS: u64 = 34_560;
const NU7_EXPIRY_MODULUS: u64 = 103_680;
/// The app's polling makes several broadcast passes per 25-second block.
const BROADCASTS_PER_BLOCK: usize = 3;
/// Blocks past the last scheduled height before a waiting run fails the test.
const SCHEDULE_SLACK_BLOCKS: u64 = 20;
/// After NU6.3: sender coinbase and maturity, a send mined for 10 blocks, then
/// the run's lead before NU7.
const CROSSING_NU7_GAP: u64 = 2 + (COINBASE_MATURITY + 10) + 10 + RUN_START_BEFORE_NU7;
/// After NU6.3: the run's lead before NU7.
const MISSED_PART_NU7_GAP: u64 = 1 + RUN_START_BEFORE_NU7;
/// After NU6.3: room for one Immediate migration before the hold opens.
const IMMEDIATE_NU7_GAP: u64 = 1 + 12;

/// Crosses NU6.3 and NU7 on a Zebra regtest chain: send expiry on either side
/// of NU7 and at its edge, a Private migration stopped by the upgrade, and the
/// rest of the Orchard balance moved by a new run under NU7 durations.
#[test]
#[ignore = "requires the Dockerized NU7 regtest stack (scripts/nu7-regtest)"]
fn migration_and_sends_cross_nu7_activation() {
    let (nu6_3, nu7) = activation_heights(CROSSING_NU7_GAP);
    simple_api::configure_regtest_ironwood_activation_height(nu6_3 as u32)
        .expect("configure wallet NU6.3 activation");
    simple_api::configure_regtest_nu7_activation_height(nu7 as u32)
        .expect("configure wallet NU7 activation");
    simple_api::configure_fast_testnet_migration(true);
    run_harness("up.sh", &[]);
    run_harness("mine.sh", &["1"]);

    let tip = latest_height();
    let migrator_dir = tempfile::tempdir().expect("migrator tempdir");
    let migrator_db = path_string(&migrator_dir.path().join("zcash_wallet.db"));
    let migrator = wallet_api::import_wallet(
        MIGRATION_MNEMONIC.to_string(),
        String::new(),
        Some(tip),
        NETWORK.to_string(),
        migrator_db.clone(),
        Some("NU7 migration".to_string()),
    )
    .expect("import migration wallet");
    let sender_mnemonic = wallet_api::generate_mnemonic();
    let sender_dir = tempfile::tempdir().expect("sender tempdir");
    let sender_db = path_string(&sender_dir.path().join("zcash_wallet.db"));
    let sender = wallet_api::import_wallet(
        sender_mnemonic.clone(),
        String::new(),
        Some(tip),
        NETWORK.to_string(),
        sender_db.clone(),
        Some("NU7 sender".to_string()),
    )
    .expect("import sender wallet");

    // Orchard funds must exist before NU6.3; Ironwood coinbase comes after it.
    run_harness("fund.sh", &[&migrator.unified_address, "2"]);
    mine(COINBASE_MATURITY + 10);
    mine_to(nu6_3 + 1);
    run_harness("fund.sh", &[&sender.unified_address, "1"]);
    mine(COINBASE_MATURITY + 10);
    sync(&migrator_db);
    sync(&sender_db);
    let funded = balance(&migrator_db, &migrator.account_uuid);
    assert!(funded.orchard > 0, "migration wallet needs Orchard funds");
    assert!(
        balance(&sender_db, &sender.account_uuid).ironwood > 0,
        "sender needs Ironwood funds"
    );

    let target = latest_height() + 1;
    let txid = send_to_self(&sender_db, &sender, &sender_mnemonic);
    assert_eq!(expiry_height(&txid), target + PRE_NU7_EXPIRY_DELTA);
    mine(10);
    sync(&sender_db);

    mine_to(nu7 - RUN_START_BEFORE_NU7);
    sync(&migrator_db);
    let first = migrate(&migrator_db, &migrator.account_uuid);
    assert_eq!(first.status, "waiting_denom_confirmations");
    let first_run_id = migration_status(&migrator_db, &migrator.account_uuid)
        .active_run_id
        .expect("first run is active");

    let window = wallet_api::get_network_upgrade_window(NETWORK.into(), latest_height())
        .expect("read the upgrade window")
        .expect("NU7 is ahead");
    assert_eq!(window.next_activation_height, nu7);
    // Migrations hold from the tip 11 blocks before activation.
    let hold_starts = nu7 - 11;
    while migration_status(&migrator_db, &migrator.account_uuid).phase != "broadcast_scheduled" {
        assert!(
            latest_height() < hold_starts,
            "preparation was still running at {}",
            latest_height()
        );
        mine(1);
        sync(&migrator_db);
        advance(&migrator_db, &migrator.account_uuid);
    }
    let first_due = run_parts(&migrator_db, &first_run_id)
        .iter()
        .map(|part| part.scheduled_height)
        .min()
        .expect("the first run schedules parts");
    assert!(
        first_due < nu7,
        "a part must fall due before NU7 to exercise the hold: first at {first_due}"
    );

    // The app stays closed until the hold window, so every part is still unsent.
    mine_to(hold_starts - 4);
    sync(&sender_db);
    let txid = send_to_self(&sender_db, &sender, &sender_mnemonic);
    // A transaction signed for this branch is invalid once NU7 activates.
    assert_eq!(expiry_height(&txid), nu7 - 1);
    mine_to(hold_starts);
    while latest_height() < nu7 - 1 {
        sync(&migrator_db);
        advance(&migrator_db, &migrator.account_uuid);
        assert!(
            mempool_migration_txids(&first_run_id, &migrator_db).is_empty(),
            "a migration part was broadcast inside the hold window at {}",
            latest_height()
        );
        mine(1);
    }

    sync(&migrator_db);
    let held = run_parts(&migrator_db, &first_run_id);
    assert!(
        held.iter()
            .any(|part| part.status == "scheduled" && part.scheduled_height < nu7),
        "a part due before NU7 was held"
    );
    assert!(
        held.iter().all(|part| part.status != "broadcasted"),
        "no part is left in flight at the upgrade"
    );
    assert!(
        held.iter()
            .all(|part| part.expiry_height % PRE_NU7_EXPIRY_MODULUS == 0),
        "pre-NU7 parts use the pre-NU7 expiry modulus"
    );
    let held_statuses = part_statuses(&held);
    let stopped = migration_status(&migrator_db, &migrator.account_uuid);
    assert_eq!(
        stopped.phase, "stopped_by_upgrade",
        "the run stops once the block before NU7 is scanned: {:?}",
        stopped.message
    );
    assert!(
        stopped.active_run_id.is_none(),
        "a stopped run is a receipt"
    );

    mine(1);
    let target = latest_height() + 1;
    sync(&sender_db);
    let txid = send_to_self(&sender_db, &sender, &sender_mnemonic);
    assert_eq!(expiry_height(&txid), target + NU7_EXPIRY_DELTA);

    sync(&migrator_db);
    let second = migrate(&migrator_db, &migrator.account_uuid);
    let second_run_id = migration_status(&migrator_db, &migrator.account_uuid)
        .active_run_id
        .expect("second run is active");
    assert_ne!(second_run_id, first_run_id);
    let second_parts = run_parts(&migrator_db, &second_run_id);
    assert!(!second_parts.is_empty(), "the second run schedules parts");
    for part in &second_parts {
        assert_eq!(
            (part.scheduled_height - part.schedule_start_height) % 3,
            0,
            "NU7 delays span whole 75-second reference blocks"
        );
        assert_eq!(part.expiry_height % NU7_EXPIRY_MODULUS, 0);
    }
    let last_scheduled = second_parts
        .iter()
        .map(|part| part.scheduled_height)
        .max()
        .unwrap_or_default();
    let mut phase = second.status;
    while phase != "complete" {
        assert!(
            latest_height() <= last_scheduled + SCHEDULE_SLACK_BLOCKS,
            "second run still {phase} at {}",
            latest_height()
        );
        mine(1);
        sync(&migrator_db);
        advance(&migrator_db, &migrator.account_uuid);
        phase = migration_status(&migrator_db, &migrator.account_uuid).phase;
    }

    // The stopped run stays a receipt: a later run must not reopen or retire it.
    let phases = run_phases(&migrator_db);
    assert_eq!(
        phases,
        vec![
            (first_run_id.clone(), "stopped_by_upgrade".to_string()),
            (second_run_id, "complete".to_string()),
        ]
    );
    assert_eq!(
        part_statuses(&run_parts(&migrator_db, &first_run_id)),
        held_statuses,
        "the stopped run's parts are untouched"
    );
    let migrated = balance(&migrator_db, &migrator.account_uuid);
    assert!(migrated.ironwood > 0);
    assert!(migrated.orchard < funded.orchard);
}

/// A part broadcast before the hold that the network never mines: once the
/// upgrade stops the run, its input returns to the Orchard balance at once
/// rather than at its ZIP 318 expiry.
#[test]
#[ignore = "requires the Dockerized NU7 regtest stack (scripts/nu7-regtest)"]
fn a_part_that_misses_the_upgrade_returns_its_input_when_the_run_stops() {
    let (nu6_3, nu7) = activation_heights(MISSED_PART_NU7_GAP);
    simple_api::configure_regtest_ironwood_activation_height(nu6_3 as u32)
        .expect("configure wallet NU6.3 activation");
    simple_api::configure_regtest_nu7_activation_height(nu7 as u32)
        .expect("configure wallet NU7 activation");
    simple_api::configure_fast_testnet_migration(true);
    run_harness("up.sh", &[]);
    run_harness("mine.sh", &["1"]);

    let migrator_dir = tempfile::tempdir().expect("migrator tempdir");
    let migrator_db = path_string(&migrator_dir.path().join("zcash_wallet.db"));
    let migrator = wallet_api::import_wallet(
        MIGRATION_MNEMONIC.to_string(),
        String::new(),
        Some(latest_height()),
        NETWORK.to_string(),
        migrator_db.clone(),
        Some("NU7 migration".to_string()),
    )
    .expect("import migration wallet");
    run_harness("fund.sh", &[&migrator.unified_address, "2"]);
    mine(COINBASE_MATURITY + 10);
    mine_to(nu6_3 + 1);
    mine_to(nu7 - RUN_START_BEFORE_NU7);
    sync(&migrator_db);
    migrate(&migrator_db, &migrator.account_uuid);
    let run_id = migration_status(&migrator_db, &migrator.account_uuid)
        .active_run_id
        .expect("run is active");
    let hold_starts = nu7 - 11;
    let broadcast = |db: &str| {
        run_parts(db, &run_id)
            .into_iter()
            .find(|part| part.status == "broadcasted")
    };
    // The Orchard total just before the pass that sends the first part.
    let mut orchard_before = 0;
    while migration_status(&migrator_db, &migrator.account_uuid).phase != "broadcast_scheduled" {
        assert!(
            latest_height() < hold_starts,
            "preparation ran into the hold"
        );
        mine(1);
        sync(&migrator_db);
        orchard_before = orchard_total(&balance(&migrator_db, &migrator.account_uuid));
        advance(&migrator_db, &migrator.account_uuid);
    }

    // Broadcast the first due part before the hold.
    let first_due = run_parts(&migrator_db, &run_id)
        .iter()
        .map(|part| part.scheduled_height)
        .min()
        .expect("the run schedules parts");
    assert!(
        first_due < hold_starts,
        "a part must fall due before the hold: first at {first_due}"
    );
    if broadcast(&migrator_db).is_none() {
        mine_to(first_due);
        sync(&migrator_db);
        orchard_before = orchard_total(&balance(&migrator_db, &migrator.account_uuid));
        advance(&migrator_db, &migrator.account_uuid);
    }
    let sent = broadcast(&migrator_db).expect("a part was broadcast before the hold");
    let stored_expiry = wallet_expiry_height(&migrator_db, &sent.txid_hex)
        .expect("the wallet stores the broadcast part");
    assert!(stored_expiry > nu7, "its ZIP 318 expiry runs past NU7");
    eprintln!(
        "orchard before {orchard_before}, after broadcast {}",
        describe(&balance(&migrator_db, &migrator.account_uuid))
    );

    // The node forgets it, and the chain moves past NU7 before the wallet looks again.
    run_harness("drop-mempool.sh", &[]);
    mine_to(nu7 + 1);
    sync(&migrator_db);

    let status = migration_status(&migrator_db, &migrator.account_uuid);
    assert_eq!(status.phase, "stopped_by_upgrade", "{:?}", status.message);
    eprintln!(
        "after stop {}",
        describe(&balance(&migrator_db, &migrator.account_uuid))
    );
    assert_eq!(
        wallet_expiry_height(&migrator_db, &sent.txid_hex),
        Some(nu7 - 1),
        "the wallet expires the unminable part at the last pre-NU7 block"
    );
    assert_eq!(
        orchard_total(&balance(&migrator_db, &migrator.account_uuid)),
        orchard_before,
        "the part's input is back in the Orchard balance"
    );
}

/// An Immediate migration sent just before the hold is mined on the old
/// branch; one inside the hold is refused with its inputs left spendable, and
/// goes through once NU7 activates.
#[test]
#[ignore = "requires the Dockerized NU7 regtest stack (scripts/nu7-regtest)"]
fn an_immediate_migration_is_held_at_the_upgrade_and_sent_after_it() {
    let (nu6_3, nu7) = activation_heights(IMMEDIATE_NU7_GAP);
    simple_api::configure_regtest_ironwood_activation_height(nu6_3 as u32)
        .expect("configure wallet NU6.3 activation");
    simple_api::configure_regtest_nu7_activation_height(nu7 as u32)
        .expect("configure wallet NU7 activation");
    run_harness("up.sh", &[]);
    run_harness("mine.sh", &["1"]);

    let tip = latest_height();
    let early_dir = tempfile::tempdir().expect("early tempdir");
    let early_db = path_string(&early_dir.path().join("zcash_wallet.db"));
    let early = wallet_api::import_wallet(
        MIGRATION_MNEMONIC.to_string(),
        String::new(),
        Some(tip),
        NETWORK.to_string(),
        early_db.clone(),
        Some("NU7 immediate before the hold".to_string()),
    )
    .expect("import early wallet");
    let late_mnemonic = wallet_api::generate_mnemonic();
    let late_dir = tempfile::tempdir().expect("late tempdir");
    let late_db = path_string(&late_dir.path().join("zcash_wallet.db"));
    let late = wallet_api::import_wallet(
        late_mnemonic.clone(),
        String::new(),
        Some(tip),
        NETWORK.to_string(),
        late_db.clone(),
        Some("NU7 immediate in the hold".to_string()),
    )
    .expect("import late wallet");

    // Orchard coinbase before NU6.3, so both wallets have Orchard to migrate.
    run_harness("fund.sh", &[&early.unified_address, "2"]);
    run_harness("fund.sh", &[&late.unified_address, "2"]);
    mine(COINBASE_MATURITY + 10);
    mine_to(nu6_3 + 1);

    mine_to(nu7 - 12);
    sync(&early_db);
    let sent = migrate_immediately(&early_db, &early.account_uuid, MIGRATION_MNEMONIC)
        .expect("an Immediate migration one block before the hold is sent");
    let txid = sent.txids.split(',').next().expect("immediate txid");
    // ZIP 318 canonical expiry, past NU7: only the hold's lead keeps it minable.
    let early_expiry = expiry_height(txid);
    assert!(
        early_expiry > nu7 && early_expiry % PRE_NU7_EXPIRY_MODULUS == 0,
        "expiry {early_expiry}"
    );
    mine(1);
    sync(&early_db);
    let migrated = balance(&early_db, &early.account_uuid);
    assert!(
        migrated.ironwood + migrated.ironwood_pending > 0,
        "mined before NU7: {}",
        describe(&migrated)
    );

    sync(&late_db);
    let before = balance(&late_db, &late.account_uuid);
    assert!(before.orchard > 0, "{}", describe(&before));
    let Err(refused) = migrate_immediately(&late_db, &late.account_uuid, &late_mnemonic) else {
        panic!("an Immediate migration inside the hold is refused");
    };
    assert!(
        refused.contains("this close to the network upgrade"),
        "{refused}"
    );
    let after = balance(&late_db, &late.account_uuid);
    assert_eq!(after.orchard, before.orchard, "{}", describe(&after));
    assert_eq!(after.orchard_locked, 0, "the refusal releases its inputs");

    mine_to(nu7 + 1);
    sync(&late_db);
    let sent = migrate_immediately(&late_db, &late.account_uuid, &late_mnemonic)
        .expect("the same migration goes through after NU7");
    let txid = sent.txids.split(',').next().expect("immediate txid");
    assert!(expiry_height(txid) > nu7, "signed for the NU7 branch");
    mine(1);
    sync(&late_db);
    let migrated = balance(&late_db, &late.account_uuid);
    assert!(
        migrated.ironwood + migrated.ironwood_pending > 0,
        "mined after NU7: {}",
        describe(&migrated)
    );
}

fn migrate_immediately(
    db_path: &str,
    account_uuid: &str,
    mnemonic: &str,
) -> Result<sync_api::IronwoodMigrationResult, String> {
    let plan = sync_api::get_orchard_migration_immediate_plan(
        db_path.to_string(),
        NETWORK.to_string(),
        account_uuid.to_string(),
    )?
    .ok_or_else(|| "no Immediate plan".to_string())?;
    sync_api::migrate_orchard_to_ironwood_immediately(
        db_path.to_string(),
        lightwalletd_url(),
        NETWORK.to_string(),
        account_uuid.to_string(),
        mnemonic.as_bytes().to_vec(),
        plan.total_input_zatoshi,
        plan.fee_zatoshi,
        plan.migrated_zatoshi,
        plan.input_note_count,
    )
}

fn describe(balance: &sync_api::WalletBalance) -> String {
    format!(
        "orchard {} locked {} pending {}, ironwood {} pending {}",
        balance.orchard,
        balance.orchard_locked,
        balance.orchard_pending,
        balance.ironwood,
        balance.ironwood_pending
    )
}

fn orchard_total(balance: &sync_api::WalletBalance) -> u64 {
    balance.orchard + balance.orchard_locked + balance.orchard_pending
}

/// The wallet's expiry for `txid`, which it stores in either byte order.
fn wallet_expiry_height(db_path: &str, txid: &str) -> Option<u64> {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet DB");
    [
        hex::decode(txid).unwrap(),
        hex::decode(reversed_hex(txid)).unwrap(),
    ]
    .into_iter()
    .find_map(|blob| {
        conn.query_row(
            "SELECT expiry_height FROM transactions WHERE txid = ?1",
            [blob],
            |row| row.get::<_, u64>(0),
        )
        .ok()
    })
}

struct Part {
    status: String,
    schedule_start_height: u64,
    scheduled_height: u64,
    expiry_height: u64,
    txid_hex: String,
}

fn configured_heights() -> (u64, u64) {
    let read = |name: &str, default: u64| {
        std::env::var(name)
            .ok()
            .map(|value| value.parse().expect("activation height must be a u64"))
            .unwrap_or(default)
    };
    (
        read("NU7_REGTEST_NU63_HEIGHT", 300),
        read("NU7_REGTEST_NU7_HEIGHT", 600),
    )
}

/// The stack accepts any NU7 above NU6.3; a scenario refuses a gap it cannot use.
fn activation_heights(min_gap: u64) -> (u64, u64) {
    let (nu6_3, nu7) = configured_heights();
    assert!(
        nu7 >= nu6_3 + min_gap,
        "this scenario needs NU7_REGTEST_NU7_HEIGHT at least {min_gap} blocks after \
         NU7_REGTEST_NU63_HEIGHT"
    );
    (nu6_3, nu7)
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

fn run_harness(script: &str, args: &[&str]) -> String {
    let (nu6_3, nu7) = configured_heights();
    let path = repo_root().join("scripts").join("nu7-regtest").join(script);
    let output = Command::new(path)
        .args(args)
        .current_dir(repo_root())
        .env("NU7_REGTEST_NU63_HEIGHT", nu6_3.to_string())
        .env("NU7_REGTEST_NU7_HEIGHT", nu7.to_string())
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

fn rpc(method: &str, params: &str) -> serde_json::Value {
    serde_json::from_str(&run_harness("rpc.sh", &[method, params])).expect("rpc returns JSON")
}

fn lightwalletd_url() -> String {
    let port =
        std::env::var("NU7_REGTEST_LIGHTWALLETD_PORT").unwrap_or_else(|_| "49067".to_string());
    format!("http://127.0.0.1:{port}")
}

fn latest_height() -> u64 {
    wallet_api::get_latest_block_height(lightwalletd_url(), NETWORK.into())
        .expect("read NU7 regtest tip")
}

fn mine(blocks: u64) {
    run_harness("mine.sh", &[&blocks.to_string()]);
}

fn mine_to(height: u64) {
    let tip = latest_height();
    if tip < height {
        mine(height - tip);
    }
}

fn sync(db_path: &str) {
    sync_api::run_full_sync_blocking(
        db_path.to_string(),
        lightwalletd_url(),
        NETWORK.to_string(),
        1,
    )
    .expect("sync wallet");
}

fn balance(db_path: &str, account_uuid: &str) -> sync_api::WalletBalance {
    sync_api::get_balance(
        db_path.to_string(),
        NETWORK.to_string(),
        account_uuid.to_string(),
    )
    .expect("wallet balance")
}

fn send_to_self(db_path: &str, wallet: &wallet_api::WalletImportResult, mnemonic: &str) -> String {
    let flow_id = format!("nu7-send-{}", latest_height());
    let proposal = sync_api::propose_send(
        db_path.to_string(),
        NETWORK.to_string(),
        wallet.account_uuid.clone(),
        flow_id.clone(),
        wallet.unified_address.clone(),
        SEND_ZATOSHI,
        None,
    )
    .expect("propose send");
    let result = sync_api::execute_proposal(
        db_path.to_string(),
        lightwalletd_url(),
        proposal.proposal_id,
        flow_id,
        mnemonic.as_bytes().to_vec(),
        None,
        None,
    )
    .expect("execute send");
    result
        .txids
        .split(',')
        .next()
        .expect("send txid")
        .to_string()
}

fn expiry_height(txid: &str) -> u64 {
    rpc("getrawtransaction", &format!("[\"{txid}\", 1]"))["expiryheight"]
        .as_u64()
        .expect("transaction reports its expiry height")
}

fn mempool_migration_txids(run_id: &str, db_path: &str) -> BTreeSet<String> {
    let mempool = rpc("getrawmempool", "[]")
        .as_array()
        .expect("mempool is a list")
        .iter()
        .filter_map(|txid| txid.as_str().map(str::to_string))
        .collect::<BTreeSet<_>>();
    run_parts(db_path, run_id)
        .into_iter()
        .map(|part| part.txid_hex)
        .filter(|txid| mempool.contains(txid) || mempool.contains(&reversed_hex(txid)))
        .collect()
}

/// Stored txids may use either byte order.
fn reversed_hex(txid: &str) -> String {
    (0..txid.len())
        .step_by(2)
        .rev()
        .map(|index| &txid[index..index + 2])
        .collect()
}

fn migration_status(db_path: &str, account_uuid: &str) -> sync_api::MigrationStatus {
    sync_api::get_orchard_migration_status(
        db_path.to_string(),
        NETWORK.to_string(),
        account_uuid.to_string(),
    )
    .expect("read migration status")
}

/// Starts a run when none is active; otherwise continues the active one.
fn migrate(db_path: &str, account_uuid: &str) -> sync_api::IronwoodMigrationResult {
    let approved_schedule = if migration_status(db_path, account_uuid)
        .active_run_id
        .is_some()
    {
        Vec::new()
    } else {
        sync_api::get_orchard_migration_private_plan(
            db_path.to_string(),
            NETWORK.to_string(),
            account_uuid.to_string(),
            false,
        )
        .expect("read migration plan")
        .map(|plan| plan.scheduled_transfers)
        .unwrap_or_default()
    };
    sync_api::migrate_orchard_to_ironwood(
        db_path.to_string(),
        lightwalletd_url(),
        NETWORK.to_string(),
        account_uuid.to_string(),
        MIGRATION_MNEMONIC.as_bytes().to_vec(),
        PENDING_PASSWORD.to_string(),
        PENDING_SALT_BASE64.to_string(),
        approved_schedule,
        false,
    )
    .expect("migrate Orchard to Ironwood")
}

/// Does what the foreground app does each block for an active run. The app
/// broadcasts one due part per pass, which also redraws overdue parts across
/// the wallet.
fn advance(db_path: &str, account_uuid: &str) {
    let status = migration_status(db_path, account_uuid);
    if status.active_run_id.is_none() {
        return;
    }
    if status.phase != "broadcast_scheduled" {
        migrate(db_path, account_uuid);
        return;
    }
    for _ in 0..BROADCASTS_PER_BLOCK {
        sync_api::broadcast_one_due_orchard_migration_transaction(
            db_path.to_string(),
            lightwalletd_url(),
            NETWORK.to_string(),
            account_uuid.to_string(),
            PENDING_PASSWORD.to_string(),
            PENDING_SALT_BASE64.to_string(),
            None,
        )
        .expect("broadcast a due migration part");
    }
}

fn run_parts(db_path: &str, run_id: &str) -> Vec<Part> {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet DB");
    let mut stmt = conn
        .prepare(
            "SELECT status, COALESCE(schedule_start_height, 0), scheduled_height,
                    expiry_height, txid_hex
             FROM vizor_migration_pending_txs
             WHERE run_id = ?1
             ORDER BY part_index",
        )
        .expect("prepare part query");
    stmt.query_map([run_id], |row| {
        Ok(Part {
            status: row.get(0)?,
            schedule_start_height: row.get(1)?,
            scheduled_height: row.get(2)?,
            expiry_height: row.get(3)?,
            txid_hex: row.get(4)?,
        })
    })
    .expect("query parts")
    .collect::<Result<_, _>>()
    .expect("read parts")
}

fn part_statuses(parts: &[Part]) -> Vec<(String, String)> {
    parts
        .iter()
        .map(|part| (part.txid_hex.clone(), part.status.clone()))
        .collect()
}

fn run_phases(db_path: &str) -> Vec<(String, String)> {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet DB");
    let mut stmt = conn
        .prepare("SELECT run_id, phase FROM vizor_migration_runs ORDER BY created_at_ms")
        .expect("prepare run query");
    stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query runs")
        .collect::<Result<_, _>>()
        .expect("read runs")
}
