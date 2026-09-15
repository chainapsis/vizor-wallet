//! Opt-in, isolated chain: funds at heights 1/2, Sapling at 200, import at 350.
//! Does not reset or connect to the developer's existing regtest services.
use super::*;
use std::{
    fs,
    process::Command,
    time::{Duration, Instant},
};

const ZCASHD: &str =
    "electriccoinco/zcashd@sha256:40cdcad6c32da8bedacf77caba149198c7674f79aeced4043128ffb3e967efba";
const LIGHTWALLETD: &str = "electriccoinco/lightwalletd@sha256:a3dfb04b4054b78ae3107dcc804c3a15a6e38d1f0dfcadeac48da482dd1d3448";

fn docker(args: &[&str]) -> String {
    let result = Command::new("docker").args(args).output().unwrap();
    assert!(
        result.status.success(),
        "docker {args:?}: {}\n{}",
        String::from_utf8_lossy(&result.stderr),
        String::from_utf8_lossy(&result.stdout)
    );
    String::from_utf8(result.stdout).unwrap().trim().to_string()
}

struct Chain {
    dir: tempfile::TempDir,
    node: String,
    lwd: String,
}

impl Drop for Chain {
    fn drop(&mut self) {
        for name in [&self.lwd, &self.node] {
            let _ = Command::new("docker").args(["rm", "-f", name]).output();
        }
    }
}

impl Chain {
    fn cli(&self, args: &[&str]) -> String {
        let mut command = vec![
            "exec",
            self.node.as_str(),
            "zcash-cli",
            "-conf=/work/zcash.conf",
        ];
        command.extend_from_slice(args);
        docker(&command)
    }

    fn ready(&self) {
        let deadline = Instant::now() + Duration::from_secs(60);
        loop {
            let result = Command::new("docker")
                .args([
                    "exec",
                    &self.node,
                    "zcash-cli",
                    "-conf=/work/zcash.conf",
                    "getblockcount",
                ])
                .output()
                .unwrap();
            if result.status.success() {
                return;
            }
            assert!(
                Instant::now() < deadline,
                "node startup timed out: {}",
                docker(&["logs", &self.node])
            );
            std::thread::sleep(Duration::from_millis(300));
        }
    }

    fn config(&self, miner: Option<&str>) {
        let mut config = String::from("regtest=1\nserver=1\nlisten=0\ndiscover=0\ndnsseed=0\ntxindex=1\nexperimentalfeatures=1\nlightwalletd=1\ninsightexplorer=1\nrpcuser=recovery\nrpcpassword=recovery\nrpcport=18232\nrpcbind=127.0.0.1\nrpcallowip=127.0.0.1\ni-am-aware-zcashd-will-be-replaced-by-zebrad-and-zallet-in-2025=1\n");
        // All upgrades used by the ordinary regtest wallet are active by import.
        // Receipts at heights 1 and 2 are genuinely pre-Overwinter/pre-Sapling.
        for branch in [
            "5ba81b19", "76b809bb", "2bb40e60", "f5b9230b", "e9ff75a6", "c2d6d0b4", "c8e71055",
            "4dec4df0", "5437f330",
        ] {
            config.push_str(&format!("nuparams={branch}:200\n"));
        }
        if let Some(address) = miner {
            config.push_str(&format!("mineraddress={address}\nminetolocalwallet=0\n"));
        }
        fs::write(self.dir.path().join("zcash.conf"), config).unwrap();
    }

    fn restart(&self, miner: Option<&str>) {
        docker(&["stop", &self.node]);
        self.config(miner);
        docker(&["start", &self.node]);
        self.ready();
    }
}

#[test]
#[ignore = "requires Docker; creates an isolated pre-Sapling regtest chain and proves recovered funds can be shielded"]
fn pre_sapling_recovery_shields_and_other_wallet_detects_the_spend() {
    let seed_phrase = keys::generate_mnemonic();
    let seed = keys::mnemonic_to_seed(&seed_phrase).unwrap();
    let addresses =
        keys::software_account_transparent_addresses(WalletNetwork::Regtest, &seed, 0, 1).unwrap();
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    let chain = Chain {
        // /tmp works as a Docker Desktop bind mount on macOS as well as Linux.
        dir: tempfile::Builder::new()
            .prefix("vizor-utxo-chain-")
            .tempdir_in("/tmp")
            .unwrap(),
        node: format!("vizor-utxo-node-{suffix}"),
        lwd: format!("vizor-utxo-lwd-{suffix}"),
    };
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(chain.dir.path(), fs::Permissions::from_mode(0o777)).unwrap();
    }
    chain.config(Some(&addresses[0]));
    let mount = format!("{}:/work", chain.dir.path().display());
    docker(&[
        "run",
        "-d",
        "--name",
        &chain.node,
        "--platform",
        "linux/amd64",
        "-p",
        "127.0.0.1::9067",
        "-v",
        &mount,
        "--entrypoint",
        "zcashd",
        ZCASHD,
        "-conf=/work/zcash.conf",
        "-datadir=/work",
        "-printtoconsole",
    ]);
    chain.ready();
    chain.cli(&["generate", "1"]);
    chain.restart(Some(&addresses[1]));
    chain.cli(&["generate", "1"]);
    chain.restart(None);
    chain.cli(&["generate", "348"]);
    fs::write(
        chain.dir.path().join("lightwalletd.conf"),
        "rpcuser=recovery\nrpcpassword=recovery\nrpcconnect=127.0.0.1\nrpcport=18232\n",
    )
    .unwrap();
    let network = format!("container:{}", chain.node);
    docker(&[
        "run",
        "-d",
        "--name",
        &chain.lwd,
        "--platform",
        "linux/amd64",
        "--network",
        &network,
        "-v",
        &mount,
        "--entrypoint",
        "lightwalletd",
        LIGHTWALLETD,
        "--no-tls-very-insecure",
        "--grpc-bind-addr",
        "0.0.0.0:9067",
        "--zcash-conf-path",
        "/work/lightwalletd.conf",
        "--data-dir",
        "/work/lwd",
        "--log-file",
        "/dev/stdout",
    ]);
    let endpoint = format!("http://{}", docker(&["port", &chain.node, "9067/tcp"]));
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        if crate::api::wallet::get_latest_block_height(endpoint.clone(), "regtest".into()).ok()
            == Some(350)
        {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "lightwalletd startup: {}",
            docker(&["logs", &chain.lwd])
        );
        std::thread::sleep(Duration::from_millis(300));
    }
    let sender = tempfile::tempdir().unwrap();
    let observer = tempfile::tempdir().unwrap();
    let sender_path = sender
        .path()
        .join("wallet.db")
        .to_str()
        .unwrap()
        .to_string();
    let observer_path = observer
        .path()
        .join("wallet.db")
        .to_str()
        .unwrap()
        .to_string();
    let import = |path: &str| {
        crate::api::wallet::import_wallet(
            seed_phrase.clone(),
            String::new(),
            Some(350),
            "regtest".into(),
            path.into(),
            Some("recovery".into()),
        )
        .unwrap()
    };
    let sender_account = import(&sender_path);
    let mut observer_account = import(&observer_path);
    // Existing v3 account: completion from a birthday-bounded lookup is retained
    // on upgrade. Exercise the supported targeted recovery path (delete/re-import)
    // while another account remains in the same wallet database.
    let external = keys::get_external_transparent_receive_addresses_from_db(
        &observer_path,
        WalletNetwork::Regtest,
        Some(&observer_account.account_uuid),
    )
    .unwrap();
    let old_plan = transparent_receive_cache::plan_external_utxo_refresh(
        &observer_path,
        WalletNetwork::Regtest,
        &observer_account.account_uuid,
        &external,
        350,
        350,
        20,
        20,
    )
    .unwrap();
    for batch in old_plan {
        transparent_receive_cache::mark_utxo_refresh_batch_complete(
            &observer_path,
            WalletNetwork::Regtest,
            &observer_account.account_uuid,
            &batch.child_indices,
            351,
            batch.next_sweep_offset,
        )
        .unwrap();
    }
    let other_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    keys::add_account(
        &observer_path,
        WalletNetwork::Regtest,
        "other",
        &other_seed,
        Some(350),
    )
    .unwrap();
    let old_uuid = observer_account.account_uuid.clone();
    crate::api::wallet::delete_account(observer_path.clone(), "regtest".into(), old_uuid.clone())
        .unwrap();
    observer_account.account_uuid = keys::add_account(
        &observer_path,
        WalletNetwork::Regtest,
        "reimported",
        &seed,
        Some(350),
    )
    .unwrap()
    .0;
    assert_ne!(observer_account.account_uuid, old_uuid);
    let sync = |path: &str| {
        crate::api::sync::run_full_sync_blocking(path.into(), endpoint.clone(), "regtest".into(), 1)
            .unwrap()
    };
    for path in [&sender_path, &observer_path] {
        sync(path);
        // Repeated same-tip sync must not add duplicate outputs.
        sync(path);
        let conn = rusqlite::Connection::open(path).unwrap();
        let recovered: i64 = conn.query_row("SELECT COUNT(*) FROM transparent_received_outputs u JOIN transactions t ON t.id_tx=u.transaction_id WHERE t.mined_height IN (1,2)", [], |r| r.get(0)).unwrap();
        assert_eq!(recovered, 2, "external and internal pre-Sapling receipts");
        let birthday: i64 = conn
            .query_row("SELECT birthday_height FROM accounts", [], |r| r.get(0))
            .unwrap();
        assert_eq!(birthday, 350);
    }
    let result = crate::api::sync::shield_transparent_balance(
        sender_path.clone(),
        endpoint.clone(),
        "regtest".into(),
        sender_account.account_uuid.clone(),
        seed_phrase.as_bytes().to_vec(),
    )
    .unwrap();
    assert!(
        result.broadcasted_count > 0,
        "{}",
        result.message.unwrap_or_default()
    );
    assert!(result.shielded_zatoshi > 0);
    chain.cli(&["generate", "10"]);
    // Wait for the indexer before sync; never treat an old tip as spend evidence.
    let deadline = Instant::now() + Duration::from_secs(60);
    while crate::api::wallet::get_latest_block_height(endpoint.clone(), "regtest".into()).unwrap()
        < 360
    {
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(300));
    }
    sync(&sender_path);
    sync(&observer_path);
    for (path, account) in [
        (&sender_path, &sender_account.account_uuid),
        (&observer_path, &observer_account.account_uuid),
    ] {
        let balance =
            crate::api::sync::get_balance(path.into(), "regtest".into(), account.into()).unwrap();
        assert_eq!(
            balance.transparent, 0,
            "a second wallet must detect the spend too"
        );
        assert!(
            balance.orchard > 0,
            "shielded output must be mined and recovered"
        );
    }
    eprintln!("Pre-Sapling external/internal UTXOs recovered at birthday 350; shielding mined; second wallet detected spend.");
}
