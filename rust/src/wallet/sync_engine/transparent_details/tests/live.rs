//! Opt-in: private txid display lookups against the live service, through
//! the real client and transport, persisting nothing (Stage 0).
//!
//! Requests reach the service through the wallet's route; the transport's
//! request observer only records them. Set `VIZOR_TRANSPARENT_PIR_LIVE_TOR=1`
//! to route them through Tor:
//!
//! ```sh
//! cargo test --manifest-path rust/Cargo.toml -- --ignored txid_live
//! VIZOR_TRANSPARENT_PIR_LIVE_TOR=1 cargo test --manifest-path rust/Cargo.toml -- --ignored txid_live
//! ```

use std::sync::{Arc, Mutex};

use zakura_pir_transparent::{Placement, TxidDisplayClient, TxidLookup};

use super::super::source::{BlockingLookup, DEFAULT_MAINNET_ORIGIN};
use super::*;
use crate::wallet::sync_engine::transparent_ledger::tests::pir::assert_private;

/// Routes the run through Tor when set to `1`.
const TOR: &str = "VIZOR_TRANSPARENT_PIR_LIVE_TOR";

/// A mainnet transaction inside the published window: one transparent input,
/// one P2PKH output, an exact fee of 20,000 zatoshis.
const TXID_DISPLAY: &str = "bc1b6edb46d71b925b7106055a9f9799ee7e0b867ccccc90d74296f91bb430da";
const HEIGHT: u64 = 3_460_000;
const RECIPIENT: &str = "t1Ku2KLyndDPsR32jwnrTMd3yvi9tfFP8ML";
const AMOUNT: u64 = 228_420_040;

fn protocol_order(display: &str) -> [u8; 32] {
    let mut bytes: [u8; 32] = hex::decode(display).unwrap().try_into().unwrap();
    bytes.reverse();
    bytes
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "requires network: https://transparent-pir.valargroup.dev"]
async fn txid_live() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let _route = crate::network_privacy::test_route_policy::lock_route_policy();
    let dir = tempfile::tempdir().unwrap();
    let tor = std::env::var(TOR).is_ok_and(|value| value == "1");
    if tor {
        crate::network_privacy::enable_tor(&dir.path().join("tor"))
            .await
            .expect("Tor bootstraps");
        assert!(crate::network_privacy::is_tor_desired());
    }
    let txid = protocol_order(TXID_DISPLAY);
    let observer = RequestObserver::recording();
    let client = Arc::new(Mutex::new(TxidDisplayClient::new()));
    let lookup = |txid: [u8; 32], height: u64| {
        let (client, observer) = (client.clone(), observer.clone());
        let handle = tokio::runtime::Handle::current();
        tokio::task::spawn_blocking(move || {
            let started = Instant::now();
            let (found, _) = BlockingLookup {
                origin: DEFAULT_MAINNET_ORIGIN.to_owned(),
                client,
                txid,
                mined_height: height,
                handle,
                cancel: Default::default(),
                observer: Some(observer),
            }
            .run();
            (found, started.elapsed())
        })
    };
    let queries = |observer: &RequestObserver| {
        observer
            .requests()
            .iter()
            .filter(|request| request.path.contains("/query/"))
            .count()
    };

    // Found: the complete output list and the fee metadata.
    let (found, took) = lookup(txid, HEIGHT).await.unwrap();
    let found = found.expect("the lookup succeeds");
    let TxidLookup::Found { provenance, .. } = &found else {
        panic!("found the transaction: {found:?}");
    };
    let (shard, tier) = (provenance.shard_id, provenance.tier.as_str());
    let answer = debug_answer(MAIN, found, HEIGHT).unwrap();
    assert_eq!(answer.outcome, "found");
    assert!(!answer.coinbase);
    assert_eq!(answer.fee, Some(20_000));
    assert_eq!(answer.transparent_input_count, 1);
    assert_eq!(answer.outputs, [(AMOUNT, Some(RECIPIENT.to_owned()))]);
    let sent = queries(&observer);
    assert!(sent >= 2, "two directory queries at least");
    eprintln!(
        "txid_live: found via {} in {:.1}s, {sent} private queries, shard {shard} ({tier})",
        if tor { "Tor" } else { "direct" },
        took.as_secs_f64(),
    );

    // Absent: an unpublished txid in the same shard sends the same two
    // directory queries and finds nothing.
    let (absent, _) = lookup([0x5a; 32], HEIGHT).await.unwrap();
    assert!(matches!(absent, Ok(TxidLookup::Absent)), "{absent:?}");
    assert_eq!(queries(&observer), sent + 2);

    // Placement unknown: a height below the published window sends no query.
    let (unplaced, _) = lookup(txid, 1_000_000).await.unwrap();
    assert!(
        matches!(unplaced, Ok(TxidLookup::PlacementUnknown(Placement::Below))),
        "{unplaced:?}"
    );
    assert_eq!(queries(&observer), sent + 2);

    // Every request used a txid display route, and none carried the txid.
    assert_private(&observer.requests(), &[txid.to_vec(), [0x5a; 32].to_vec()]);
}
