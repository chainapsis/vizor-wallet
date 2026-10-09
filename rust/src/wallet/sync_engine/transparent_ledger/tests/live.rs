//! Opt-in: private recovery of a fresh mainnet account from the live
//! transparent PIR service, through the real source and transport.
//!
//! The wallet's chain is synthetic. A test cannot scan mainnet, so it reads
//! the published shard map first, gives the account a birthday at the start
//! of the last sealed shard, and records blocks from there through the end of
//! the map, with the map's own block hashes at every shard boundary in that
//! range and arbitrary hashes elsewhere. The adapter checks the wallet's
//! chain only at those boundaries and at the target, so the publication is
//! accepted exactly as on the real chain. A fresh account has no transparent
//! history, so recovery completes empty and the account is promoted with a
//! current balance of zero.
//!
//! Requests reach the service through the wallet's route; the transport's
//! request observer only records them. Set
//! `VIZOR_TRANSPARENT_PIR_LIVE_TOR=1` to route them through Tor:
//!
//! ```sh
//! cargo test --manifest-path rust/Cargo.toml -- --ignored a_fresh_mainnet_account
//! VIZOR_TRANSPARENT_PIR_LIVE_TOR=1 cargo test --manifest-path rust/Cargo.toml -- --ignored a_fresh_mainnet_account
//! ```

use std::collections::{BTreeMap, BTreeSet};

use zakura_pir_transparent::{FilterSource, TransparentPirHttp};

use super::super::pir::{test_transport, TransparentPirSource, DEFAULT_MAINNET_ORIGIN};
use super::super::policy::POLICY_DRAIN;
use super::pir::assert_private;
use super::*;
use crate::wallet::sync_engine::enhancement::{RequestObserver, RoutePolicy, RoutedExchange};

const MAIN: WalletNetwork = WalletNetwork::Main;
/// Routes the run through Tor when set to `1`.
const TOR: &str = "VIZOR_TRANSPARENT_PIR_LIVE_TOR";
/// Bytes the shard map may take, as for a recovery pass.
const MAP_LIMIT: usize = 8 << 20;

/// One shard-map entry, as the test needs it.
struct Shard {
    id: u64,
    start: u32,
    end: u32,
    parent: String,
    terminal: String,
    sealed: bool,
}

/// The live shard map's entries, fetched through the wallet's route.
async fn published() -> Vec<Shard> {
    let handle = tokio::runtime::Handle::current();
    let map: serde_json::Value = tokio::task::spawn_blocking(move || {
        let exit = || false;
        let exchange = RoutedExchange::transparent(DEFAULT_MAINNET_ORIGIN, &exit, handle)
            .expect("the default origin is HTTPS");
        let mut http = TransparentPirHttp::new(exchange, MAP_LIMIT);
        let (mut filters, _) = http.split();
        let (bytes, _) = filters.shard_map().expect("the service publishes a map");
        serde_json::from_slice(&bytes).expect("the map is JSON")
    })
    .await
    .unwrap();
    assert_eq!(map["network"], "main", "a mainnet publication");
    let height = |value: &serde_json::Value| u32::try_from(value.as_u64().unwrap()).unwrap();
    map["shards"]
        .as_array()
        .expect("the map lists shards")
        .iter()
        .map(|shard| Shard {
            id: shard["shard_id"].as_u64().unwrap(),
            start: height(&shard["start_height"]),
            end: height(&shard["end_height"]),
            parent: shard["parent_block_hash"].as_str().unwrap().to_owned(),
            terminal: shard["terminal_block_hash"].as_str().unwrap().to_owned(),
            sealed: shard["sealed"].as_bool().unwrap(),
        })
        .collect()
}

/// The ids of `shards` that overlap `[floor, target]`.
fn overlapping(shards: &[Shard], floor: u32, target: u32) -> BTreeSet<u64> {
    shards
        .iter()
        .filter(|shard| shard.start <= target && shard.end >= floor)
        .map(|shard| shard.id)
        .collect()
}

/// A block hash in the wallet's byte order, from the map's display hex.
fn internal(display: &str) -> Vec<u8> {
    let mut bytes = hex::decode(display).expect("a hex block hash");
    bytes.reverse();
    bytes
}

/// Records blocks `floor..=target`, hashed as the map says at its shard
/// boundaries, and marks the wallet scanned through `target`.
fn record_chain(path: &str, floor: u32, target: u32, shards: &[Shard]) {
    let in_range = |height: u32| (floor..=target).contains(&height);
    let mut boundaries = BTreeMap::new();
    for shard in shards {
        if let Some(below) = shard.start.checked_sub(1).filter(|h| in_range(*h)) {
            boundaries.insert(below, internal(&shard.parent));
        }
    }
    for shard in shards.iter().filter(|shard| in_range(shard.end)) {
        boundaries.insert(shard.end, internal(&shard.terminal));
    }
    let mut conn = rusqlite::Connection::open(path).unwrap();
    let tx = conn.transaction().unwrap();
    for height in floor..=target {
        let hash = boundaries
            .get(&height)
            .cloned()
            .unwrap_or_else(|| main_hash(height).0.to_vec());
        tx.execute(
            "INSERT OR REPLACE INTO blocks (height, hash, time, sapling_tree,
                 sapling_commitment_tree_size, orchard_commitment_tree_size,
                 ironwood_commitment_tree_size)
             VALUES (?1, ?2, 0, x'00', 0, 0, 0)",
            rusqlite::params![height, hash],
        )
        .unwrap();
    }
    tx.execute_batch(&format!(
        "DELETE FROM scan_queue;
         INSERT INTO scan_queue (block_range_start, block_range_end, priority)
         VALUES ({floor}, {}, 10);",
        target + 1
    ))
    .unwrap();
    tx.commit().unwrap();
}

/// The key or script hash of every address `account` watches.
fn watched_hashes(db: &WalletDatabase, account: AccountUuid) -> BTreeSet<Vec<u8>> {
    db.transparent_watch_set(account)
        .unwrap()
        .addresses
        .into_iter()
        .map(|watched| match watched.address {
            TransparentAddress::PublicKeyHash(hash) | TransparentAddress::ScriptHash(hash) => {
                hash.to_vec()
            }
        })
        .collect()
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "requires network: https://transparent-pir.valargroup.dev"]
async fn a_fresh_mainnet_account_recovers_and_promotes_against_the_live_service() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let _route = crate::network_privacy::test_route_policy::lock_route_policy();
    let dir = tempfile::tempdir().unwrap();
    if std::env::var(TOR).is_ok_and(|value| value == "1") {
        crate::network_privacy::enable_tor(&dir.path().join("tor"))
            .await
            .expect("Tor bootstraps");
        assert!(crate::network_privacy::is_tor_desired());
    }

    // The birthday is the start of the last sealed shard, and the wallet's
    // chain ends where the map does.
    let before = published().await;
    let last_sealed = before
        .iter()
        .filter(|shard| shard.sealed)
        .max_by_key(|shard| shard.end)
        .expect("a sealed shard");
    let target = before.iter().map(|shard| shard.end).max().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) = keys::init_db_and_create_account(
        &path,
        MAIN,
        &seed,
        Some(u64::from(last_sealed.start)),
        "live",
    )
    .unwrap();
    let account = keys::parse_account_uuid(&uuid).unwrap();
    let floor: u32 = count(&path, "SELECT MIN(birthday_height) FROM accounts")
        .try_into()
        .unwrap();
    assert!(floor <= target);
    record_chain(&path, floor, target, &before);

    // Private queries on supported mainnet.
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    apply_transparent_policy_fenced(
        &mut db,
        &path,
        TransparentLedgerMode::PrivateRequired,
        POLICY_DRAIN,
    )
    .await
    .unwrap();
    let _mode = test_mode::set(&path, TransparentLedgerMode::PrivateRequired);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let mut secrets = watched_hashes(&db, account);

    let seam = test_transport::set(&path, RequestObserver::recording());
    let source = TransparentPirSource::new(&path, MAIN);
    let required = EnhancementPolicy::for_preference(MAIN, false)
        .with_transparent_mode(TransparentLedgerMode::PrivateRequired);
    let outcome = run(
        &mut db,
        &path,
        MAIN,
        required,
        &source,
        Some(account),
        Instant::now,
        &|| false,
    )
    .await
    .unwrap();
    drop(source);
    let RunOutcome::Finished(stats) = outcome else {
        panic!("recovery finishes: {outcome:?}");
    };
    assert_eq!(stats.promoted, 1, "{stats:?}");
    assert!(stats.qualified > 0, "{stats:?}");
    let balance = get_wallet_balance(&path, MAIN, &uuid).unwrap();
    assert_eq!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(
        (balance.transparent, balance.transparent_last_known),
        (0, None)
    );

    // Every request used a service route on the wallet's route, and none
    // carried a watched script.
    let requests = seam.seam.observer.requests();
    assert!(seam
        .seam
        .routes()
        .iter()
        .all(|route| *route == RoutePolicy::WalletPreference));
    secrets.extend(watched_hashes(&db, account));
    assert_private(&requests, &secrets.into_iter().collect::<Vec<_>>());

    // Filters were requested only for shards overlapping the birthday through
    // the target, at most one each. The map may move during the run, so
    // either publication bounds it.
    let after = published().await;
    let filter = regex::Regex::new(r"^/v1/filters/shards/([0-9]+)/filter$").unwrap();
    let filtered: Vec<u64> = requests
        .iter()
        .filter_map(|request| filter.captures(&request.path))
        .map(|captures| captures[1].parse().unwrap())
        .collect();
    let (was, is) = (
        overlapping(&before, floor, target),
        overlapping(&after, floor, target),
    );
    assert!(!filtered.is_empty(), "the pass read a filter");
    assert!(
        filtered
            .iter()
            .all(|id| was.contains(id) || is.contains(id)),
        "a filter outside the birthday through the target"
    );
    assert!(
        filtered.len() <= was.len().max(is.len()),
        "{} filter requests for {} overlapping shards",
        filtered.len(),
        was.len().max(is.len())
    );
}
