use super::*;
use std::sync::atomic::{AtomicBool, Ordering};

use super::super::test_lwd::CapturingLwd;

fn tip(height: u64) -> BlockId {
    BlockId {
        height,
        hash: vec![height as u8],
    }
}

#[test]
fn scope_control_errors_are_not_endpoint_failover_candidates() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    let original = TipRequestScope::capture();
    let cancelled = original.ensure_current(|| true).unwrap_err();
    network_privacy::begin_tor_enable();
    let changed = original.ensure_current(|| false).unwrap_err();
    let current = TipRequestScope::capture();
    let connecting = current.ensure_current(|| false).unwrap_err();
    network_privacy::fail_tor_enable();
    let failed = current.ensure_current(|| false).unwrap_err();
    for error in [cancelled, changed, connecting, failed] {
        assert!(!error.is_endpoint_failover_candidate(), "{error}");
        assert!(
            !super::super::error::is_endpoint_failover_candidate_message(&error.to_string()),
            "{error}",
        );
    }
}

#[test]
fn recent_tip_is_scoped_to_endpoint_and_network() {
    let now = Instant::now();
    let mut cache = LatestBlockCache::default();
    cache.record("https://one.example", WalletNetwork::Main, tip(42), now, 0);

    assert_eq!(
        cache
            .recent(
                "https://one.example",
                WalletNetwork::Main,
                now + Duration::from_secs(15),
                TRANSACTION_TIP_MAX_AGE,
                0,
            )
            .map(|tip| tip.height),
        Some(42)
    );
    assert!(cache
        .recent(
            "https://two.example",
            WalletNetwork::Main,
            now,
            TRANSACTION_TIP_MAX_AGE,
            0,
        )
        .is_none());
    assert!(cache
        .recent(
            "https://one.example",
            WalletNetwork::Test,
            now,
            TRANSACTION_TIP_MAX_AGE,
            0,
        )
        .is_none());
}

#[test]
fn tip_older_than_max_age_is_not_reused() {
    let now = Instant::now();
    let mut cache = LatestBlockCache::default();
    cache.record("https://one.example", WalletNetwork::Main, tip(42), now, 0);

    assert!(cache
        .recent(
            "https://one.example",
            WalletNetwork::Main,
            now + Duration::from_secs(16),
            TRANSACTION_TIP_MAX_AGE,
            0,
        )
        .is_none());
}

#[test]
fn recording_again_replaces_height_and_recency() {
    let now = Instant::now();
    let mut cache = LatestBlockCache::default();
    cache.record("https://one.example", WalletNetwork::Main, tip(41), now, 0);
    cache.record(
        "https://one.example",
        WalletNetwork::Main,
        tip(42),
        now + Duration::from_secs(10),
        0,
    );

    assert_eq!(
        cache
            .recent(
                "https://one.example",
                WalletNetwork::Main,
                now + Duration::from_secs(24),
                TRANSACTION_TIP_MAX_AGE,
                0,
            )
            .map(|tip| tip.height),
        Some(42)
    );
}

#[test]
fn a_stale_generation_lookup_cannot_reuse_or_remove_a_newer_tip() {
    let now = Instant::now();
    let mut cache = LatestBlockCache::default();
    cache.record("https://one.example", WalletNetwork::Main, tip(42), now, 2);
    assert!(cache
        .recent(
            "https://one.example",
            WalletNetwork::Main,
            now,
            TRANSACTION_TIP_MAX_AGE,
            1
        )
        .is_none());
    assert_eq!(
        cache
            .recent(
                "https://one.example",
                WalletNetwork::Main,
                now,
                TRANSACTION_TIP_MAX_AGE,
                2
            )
            .unwrap(),
        tip(42)
    );
}

async fn wait_for_tip_request(server: &CapturingLwd) {
    tokio::time::timeout(Duration::from_secs(2), async {
        while server.count("/GetLatestBlock") == 0 {
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
    })
    .await
    .expect("tip request did not reach the local server");
}

#[tokio::test]
async fn a_fresh_same_route_tip_is_reused_without_an_extra_rpc() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    let server = CapturingLwd::start_with(Vec::new(), 3_000_000, |_| {}).await;
    assert_eq!(
        latest_block_for_transaction(&server.url, WalletNetwork::Main)
            .await
            .unwrap()
            .height,
        3_000_000
    );
    assert_eq!(
        latest_block_for_transaction(&server.url, WalletNetwork::Main)
            .await
            .unwrap()
            .height,
        3_000_000
    );
    assert_eq!(server.count("/GetLatestBlock"), 1);
}

#[tokio::test]
async fn a_cached_tip_cannot_bypass_a_bootstrapping_or_failed_route() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    let server = CapturingLwd::start_with(Vec::new(), 3_000_000, |_| {}).await;
    record_latest_block(&server.url, WalletNetwork::Main, tip(3_000_000));
    network_privacy::begin_tor_enable();
    for failed in [false, true] {
        if failed {
            network_privacy::fail_tor_enable();
        }
        let error = latest_block_for_transaction(&server.url, WalletNetwork::Main)
            .await
            .unwrap_err();
        assert!(error.to_string().contains("network privacy blocked"));
    }
    assert_eq!(server.count("/GetLatestBlock"), 0);
}

#[tokio::test]
async fn returning_to_direct_invalidates_old_entries_and_existing_client_scopes() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    let stale_scope = TipRequestScope::capture();
    let server = CapturingLwd::start_with(Vec::new(), 3_000_000, |_| {}).await;
    let mut client = server.client.clone();
    get_latest_block_recorded(
        &mut client,
        &server.url,
        WalletNetwork::Main,
        stale_scope,
        || false,
    )
    .await
    .unwrap();
    network_privacy::begin_tor_enable();
    network_privacy::disable_tor();

    latest_block_for_transaction(&server.url, WalletNetwork::Main)
        .await
        .unwrap();
    assert_eq!(
        server.count("/GetLatestBlock"),
        2,
        "the old direct cache belongs to another generation"
    );
    let error = latest_block_for_transaction_with_client(
        &mut client,
        &server.url,
        WalletNetwork::Main,
        stale_scope,
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("network privacy blocked"));
    assert_eq!(
        server.count("/GetLatestBlock"),
        2,
        "a stale client cannot consume the fresh cache or issue a request"
    );
    assert_eq!(
        latest_block_for_transaction(&server.url, WalletNetwork::Main)
            .await
            .unwrap()
            .height,
        3_000_000
    );
    assert_eq!(server.count("/GetLatestBlock"), 2);
}

#[tokio::test]
async fn a_route_change_while_a_tip_is_in_flight_discards_the_response() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    let scope = TipRequestScope::capture();
    let server = CapturingLwd::start_with(Vec::new(), 3_000_100, |_| {}).await;
    // The fixture's unguarded local channel lets the old successful reply
    // arrive after the route changes, independently of transport teardown.
    let gate = server.hold_responses("/GetLatestBlock");
    let mut client = server.client.clone();
    let read =
        get_latest_block_recorded(&mut client, &server.url, WalletNetwork::Main, scope, || {
            false
        });
    let change = async {
        wait_for_tip_request(&server).await;
        network_privacy::begin_tor_enable();
        gate.notify_one();
    };
    let (result, ()) = tokio::join!(read, change);
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("network privacy blocked"));
    network_privacy::disable_tor();
    assert!(
        recent_transaction_tip(&server.url, WalletNetwork::Main, TipRequestScope::capture())
            .unwrap()
            .is_none()
    );
    gate.notify_one();
    assert_eq!(
        latest_block_for_transaction(&server.url, WalletNetwork::Main)
            .await
            .unwrap()
            .height,
        3_000_100
    );
    assert_eq!(
        server.count("/GetLatestBlock"),
        2,
        "the discarded reply did not populate the new route cache"
    );
}

#[tokio::test]
async fn an_old_route_response_cannot_overwrite_a_new_route_tip() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    let scope = TipRequestScope::capture();
    let server = CapturingLwd::start_with(Vec::new(), 3_000_100, |_| {}).await;
    let gate = server.hold_responses("/GetLatestBlock");
    let mut client = server.client.clone();
    let read =
        get_latest_block_recorded(&mut client, &server.url, WalletNetwork::Main, scope, || {
            false
        });
    let change = async {
        wait_for_tip_request(&server).await;
        network_privacy::begin_tor_enable();
        network_privacy::disable_tor();
        record_latest_block(&server.url, WalletNetwork::Main, tip(3_000_200));
        gate.notify_one();
    };
    let (result, ()) = tokio::join!(read, change);
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("network privacy blocked"));
    assert_eq!(
        latest_block_for_transaction(&server.url, WalletNetwork::Main)
            .await
            .unwrap(),
        tip(3_000_200)
    );
    assert_eq!(server.count("/GetLatestBlock"), 1);
}

#[tokio::test]
async fn cancellation_discards_an_in_flight_tip_without_erasing_completed_metadata() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    for existing in [false, true] {
        let scope = TipRequestScope::capture();
        let server = CapturingLwd::start_with(Vec::new(), 3_000_100, |_| {}).await;
        if existing {
            record_latest_block(&server.url, WalletNetwork::Main, tip(3_000_200));
        }
        let gate = server.hold_responses("/GetLatestBlock");
        let cancelled = AtomicBool::new(false);
        let mut client = server.client.clone();
        let read =
            get_latest_block_recorded(&mut client, &server.url, WalletNetwork::Main, scope, || {
                cancelled.load(Ordering::Acquire)
            });
        let cancel = async {
            wait_for_tip_request(&server).await;
            cancelled.store(true, Ordering::Release);
            gate.notify_one();
        };
        let (result, ()) = tokio::join!(read, cancel);
        assert!(result.unwrap_err().to_string().contains("cancelled"));
        if existing {
            assert_eq!(
                latest_block_for_transaction(&server.url, WalletNetwork::Main)
                    .await
                    .unwrap(),
                tip(3_000_200)
            );
            assert_eq!(server.count("/GetLatestBlock"), 1);
        } else {
            assert!(
                recent_transaction_tip(&server.url, WalletNetwork::Main, scope)
                    .unwrap()
                    .is_none()
            );
            gate.notify_one();
            assert_eq!(
                latest_block_for_transaction(&server.url, WalletNetwork::Main)
                    .await
                    .unwrap()
                    .height,
                3_000_100
            );
            assert_eq!(server.count("/GetLatestBlock"), 2);
        }
    }
}

#[tokio::test]
async fn waiting_for_a_tip_never_holds_the_cache_mutex() {
    let _route = network_privacy::test_route_policy::lock_route_policy();
    let scope = TipRequestScope::capture();
    let server = CapturingLwd::start_with(Vec::new(), 3_000_000, |_| {}).await;
    let gate = server.hold_responses("/GetLatestBlock");
    let mut client = server.client.clone();
    let read =
        get_latest_block_recorded(&mut client, &server.url, WalletNetwork::Main, scope, || {
            false
        });
    let inspect = async {
        wait_for_tip_request(&server).await;
        let mut worker = tokio::task::spawn_blocking(|| with_cache(|_| ()));
        let available = tokio::time::timeout(Duration::from_secs(1), &mut worker)
            .await
            .is_ok();
        // Always release the RPC before asserting, so a lock regression
        // unwinds both accepted operations instead of leaking a worker.
        gate.notify_one();
        if !available {
            worker.await.unwrap();
        }
        available
    };
    let (result, available) = tokio::join!(read, inspect);
    result.unwrap();
    assert!(
        available,
        "cache mutex was held while awaiting lightwalletd"
    );
}
