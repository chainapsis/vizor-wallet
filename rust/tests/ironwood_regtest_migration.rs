use std::path::{Path, PathBuf};
use std::process::Command;

use rust_lib_zcash_wallet::api::{simple as simple_api, sync as sync_api, wallet as wallet_api};

const NETWORK: &str = "regtest";
const MNEMONIC: &str = "winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used";
const PENDING_PASSWORD: &str = "ironwood-regtest-password";
const PENDING_SALT_BASE64: &str = "AAECAwQFBgcICQoLDA0ODw==";
const TRUSTED_CONFIRMATIONS: u32 = 10;

#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn orchard_funds_migrate_after_controlled_nu6_3_activation() {
    let activation_height = activation_height();
    simple_api::configure_regtest_ironwood_activation_height(activation_height)
        .expect("configure wallet NU6.3 activation");
    ensure_stack_up();

    let pre_activation_tip = latest_height();
    assert!(
        pre_activation_tip < u64::from(activation_height),
        "test must begin before NU6.3: tip={pre_activation_tip}, activation={activation_height}"
    );

    let tempdir = tempfile::tempdir().expect("wallet tempdir");
    let db_path = tempdir.path().join("zcash_wallet.db");
    let db = path_string(&db_path);
    let wallet = wallet_api::import_wallet(
        MNEMONIC.to_string(),
        Some(pre_activation_tip),
        NETWORK.to_string(),
        db.clone(),
        Some("Ironwood migration E2E".to_string()),
    )
    .expect("import deterministic regtest wallet");

    run_harness(
        "fund-orchard.sh",
        &[&wallet.unified_address, "1.0002", "10"],
    );
    sync(&db);

    let orchard_funded = balance(&db, &wallet.account_uuid);
    assert!(
        orchard_funded.orchard >= 100_020_000,
        "pre-activation funding must land in Orchard: orchard={}, ironwood={}, total={}",
        orchard_funded.orchard,
        orchard_funded.ironwood,
        orchard_funded.total
    );
    assert_eq!(
        orchard_funded.ironwood, 0,
        "Ironwood must be empty before activation"
    );
    let before = wallet_api::get_chain_upgrade_status(lightwalletd_url(), NETWORK.to_string())
        .expect("pre-activation chain status");
    assert!(!before.ironwood_active_at_tip);
    assert_eq!(
        before.nu6_3_activation_height,
        Some(u64::from(activation_height))
    );

    run_harness("activate-ironwood.sh", &[]);
    let after = wallet_api::get_chain_upgrade_status(lightwalletd_url(), NETWORK.to_string())
        .expect("post-activation chain status");
    assert!(after.ironwood_active_at_tip);
    assert_eq!(after.lightwalletd_consensus_branch_id, "37a5165b");

    sync(&db);
    let split = migrate(&db, &wallet.account_uuid);
    assert_eq!(split.status, "waiting_denom_confirmations");
    assert!(
        split.total_count > 0,
        "migration must prepare a denomination"
    );

    mine_and_sync(&db, TRUSTED_CONFIRMATIONS);
    let migration = migrate(&db, &wallet.account_uuid);
    assert!(
        matches!(
            migration.status.as_str(),
            "broadcast_scheduled" | "waiting_migration_confirmations"
        ),
        "unexpected migration broadcast phase: {} ({:?})",
        migration.status,
        migration.message
    );
    assert!(migration.broadcasted_count > 0);

    mine_and_sync(&db, TRUSTED_CONFIRMATIONS);
    let status = sync_api::get_orchard_migration_status(
        db.clone(),
        NETWORK.to_string(),
        wallet.account_uuid.clone(),
    )
    .expect("final migration status");
    assert_eq!(
        status.phase, "complete",
        "status message: {:?}",
        status.message
    );

    let migrated = balance(&db, &wallet.account_uuid);
    assert!(
        migrated.ironwood >= orchard_funded.orchard * 99 / 100,
        "migrated value must be spendable in Ironwood: orchard={}, ironwood={}, total={}",
        migrated.orchard,
        migrated.ironwood,
        migrated.total
    );
    assert!(
        migrated.ironwood < orchard_funded.orchard,
        "migration fees must reduce the migrated value: before={}, after={}",
        orchard_funded.orchard,
        migrated.ironwood
    );
    assert_eq!(
        migrated.orchard, 0,
        "the deterministic migration must consume all funded Orchard value"
    );
}

fn activation_height() -> u32 {
    std::env::var("IRONWOOD_ACTIVATION_HEIGHT")
        .unwrap_or_else(|_| "500".to_string())
        .parse()
        .expect("IRONWOOD_ACTIVATION_HEIGHT must be a u32")
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

fn ensure_stack_up() {
    run_harness("up.sh", &[]);
}

fn latest_height() -> u64 {
    wallet_api::get_latest_block_height(lightwalletd_url()).expect("read Ironwood regtest tip")
}

fn lightwalletd_url() -> String {
    let port = std::env::var("IRONWOOD_LIGHTWALLETD_PORT").unwrap_or_else(|_| "19067".to_string());
    format!("http://127.0.0.1:{port}")
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

fn mine_and_sync(db_path: &str, blocks: u32) {
    run_harness("mine.sh", &[&blocks.to_string()]);
    sync(db_path);
}

fn balance(db_path: &str, account_uuid: &str) -> sync_api::WalletBalance {
    sync_api::get_balance(
        db_path.to_string(),
        NETWORK.to_string(),
        account_uuid.to_string(),
    )
    .expect("wallet balance")
}

fn migrate(db_path: &str, account_uuid: &str) -> sync_api::IronwoodMigrationResult {
    sync_api::migrate_orchard_to_ironwood(
        db_path.to_string(),
        lightwalletd_url(),
        NETWORK.to_string(),
        account_uuid.to_string(),
        MNEMONIC.as_bytes().to_vec(),
        PENDING_PASSWORD.to_string(),
        PENDING_SALT_BASE64.to_string(),
    )
    .expect("migrate Orchard to Ironwood")
}
