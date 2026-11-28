//! Boundary checks for the registry bridge, on documents built the way the
//! chain and the config repo build them: one happy path per call, the
//! verdict mapping, and what Vizor owns (list key pinning, paging).
//! zcash_voting's own tests cover the rules behind each call. The tests run
//! on `regtest`, whose list key a harness pins.

use base64::engine::general_purpose::STANDARD as BASE64;
use ed25519_consensus::SigningKey;
use serde_json::{json, Value};
use zcash_vote_delegate::{
    DelegateKey, DelegateSigningKey, DelegateStatus, IdentityProvider, ProxyDelegateEntry,
    WalletList, WalletListRow,
};
use zcash_voting::wire::{DelegateEntryStatus, ProxyDelegateChoice, ProxyDelegateProvider};

use super::*;

/// The wallet network the tests use; its vote chain is [`CHAIN_ID`].
const NETWORK: &str = "regtest";
/// The vote chain the tests' regtest anchor names.
const CHAIN_ID: &str = "svote-1";
/// The round under test.
const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
/// When the tests' wallet list was signed.
const ISSUED_AT: u64 = 1_790_000_000;
/// The `key_id` the regtest harness signs with.
const LIST_KEY_ID: &str = "vizor-regtest";

/// The key the regtest list is signed with.
fn list_signer() -> SigningKey {
    SigningKey::from([9; 32])
}

/// Pins [`list_signer`] for regtest on the shared regtest anchor.
fn pin_regtest() {
    participation::configure_test_regtest_trust();
    configure_regtest_wallet_list_key(
        LIST_KEY_ID.to_owned(),
        BASE64.encode(list_signer().verification_key().to_bytes()),
    )
    .unwrap();
}

/// Delegate key number `seed`.
fn dk(seed: u8) -> DelegateKey {
    DelegateSigningKey::from_secret_seed([seed; 32]).delegate_key()
}

/// The active X entry `index` of `handle`, with key number `index`.
fn entry(index: u32, handle: &str) -> ProxyDelegateEntry {
    ProxyDelegateEntry {
        index,
        dk: dk(index as u8),
        provider: IdentityProvider::X,
        handle: handle.to_owned(),
        proof_id: format!("17900000000000000{index:02}"),
        status: DelegateStatus::Active,
        status_reason: 0,
        registered_height: 10,
    }
}

/// The registry under test: `alice`, `bob` suspended, `carol` retired, and
/// `a1ice`, registered after the round was created.
fn registry() -> Vec<ProxyDelegateEntry> {
    vec![
        entry(1, "alice"),
        ProxyDelegateEntry {
            status: DelegateStatus::Suspended,
            status_reason: 4,
            ..entry(2, "bob")
        },
        ProxyDelegateEntry {
            status: DelegateStatus::Retired,
            ..entry(3, "carol")
        },
        entry(21, "a1ice"),
    ]
}

/// `entry` as the REST API writes it, zero values omitted.
fn entry_json(entry: &ProxyDelegateEntry) -> Value {
    let mut value = json!({
        "index": entry.index,
        "dk": BASE64.encode(entry.dk.to_bytes()),
        "provider": entry.provider.code(),
        "handle": entry.handle,
        "proof_id": entry.proof_id,
        "registered_height": entry.registered_height,
    });
    if entry.status != DelegateStatus::Active {
        value["status"] = json!(entry.status.code());
    }
    if entry.status_reason != 0 {
        value["status_reason"] = json!(entry.status_reason);
    }
    value
}

/// A registry page holding `entries`, continuing after `next`.
fn page_body(entries: &[ProxyDelegateEntry], next: u32) -> Vec<u8> {
    let delegates: Vec<Value> = entries.iter().map(entry_json).collect();
    json!({ "delegates": delegates, "next_start_after": next })
        .to_string()
        .into_bytes()
}

/// The registry cache of [`registry`], downloaded in two pages.
fn cache_json() -> String {
    let entries = registry();
    build_proxy_registry_cache(
        NETWORK.to_owned(),
        vec![
            ApiRegistryPage {
                start_after: 0,
                body: page_body(&entries[..2], 2),
            },
            ApiRegistryPage {
                start_after: 2,
                body: page_body(&entries[2..], 0),
            },
        ],
    )
    .unwrap()
    .json
}

/// A 20-byte WebP container; only its structure is valid.
fn picture() -> Vec<u8> {
    let mut picture = b"RIFF".to_vec();
    picture.extend_from_slice(&12u32.to_le_bytes());
    picture.extend_from_slice(b"WEBPVP8L");
    picture.extend_from_slice(&[0; 4]);
    picture
}

/// Vizor's row that describes `entry`.
fn row(entry: &ProxyDelegateEntry) -> WalletListRow {
    WalletListRow {
        index: entry.index,
        provider: entry.provider.code(),
        handle: entry.handle.clone(),
        dk: entry.dk.encode(),
        name: format!("Delegate {}", entry.index),
        statement: Some(format!("Statement of {}.", entry.index)),
        picture: Some(picture()),
    }
}

/// Version `version` of Vizor's list: the first three entries of
/// [`registry`].
fn wallet_list(version: u64) -> WalletList {
    WalletList {
        wallet_id: VIZOR_WALLET_ID.to_owned(),
        chain_id: CHAIN_ID.to_owned(),
        version,
        issued_at: ISSUED_AT,
        reserved_names: vec!["zcash".to_owned()],
        delegates: registry()[..3].iter().map(row).collect(),
    }
}

/// `list` as the admin UI publishes it, signed by `signer` under `key_id`.
fn list_document(list: &WalletList, signer: &SigningKey, key_id: &str) -> Vec<u8> {
    let payload = list.payload().unwrap();
    let rows: Vec<Value> = list
        .delegates
        .iter()
        .map(|row| {
            json!({
                "index": row.index,
                "provider": row.provider,
                "handle": row.handle,
                "dk": row.dk,
                "name": row.name,
                "statement": row.statement,
                "picture": row.picture.as_ref().map(|picture| BASE64.encode(picture)),
            })
        })
        .collect();
    json!({
        "format": "zcash-vote-wallet-list/v1",
        "wallet_id": list.wallet_id,
        "chain_id": list.chain_id,
        "version": list.version,
        "issued_at": list.issued_at,
        "reserved_names": list.reserved_names,
        "delegates": rows,
        "signatures": [{
            "key_id": key_id,
            "alg": "ed25519",
            "sig": BASE64.encode(signer.sign(&payload).to_bytes()),
        }],
    })
    .to_string()
    .into_bytes()
}

/// Version `version` of Vizor's list, signed by the pinned key.
fn signed_list(version: u64) -> Vec<u8> {
    list_document(&wallet_list(version), &list_signer(), LIST_KEY_ID)
}

/// The view a delegator browses with: [`registry`] and version 1 of
/// Vizor's list, in a round with entries from 20 on new.
fn view() -> ApiProxyRegistryView {
    pin_regtest();
    ApiProxyRegistryView {
        network: NETWORK.to_owned(),
        registry_cache: cache_json(),
        wallet_list: Some(signed_list(1)),
        first_new_index: Some(20),
    }
}

/// The proof of entry `index` from [`registry`], or of its absence.
fn entry_proof(index: u32) -> ApiProvenRegistryEntry {
    ApiProvenRegistryEntry {
        delegate_index: index,
        entry: registry()
            .into_iter()
            .find(|entry| entry.index == index)
            .map(|entry| entry.encode()),
    }
}

/// The choice of `listing` as the delegator picked it.
fn choice(listing: &ProxyDelegateListing) -> ProxyDelegateChoice {
    ProxyDelegateChoice {
        delegate_index: listing.index,
        percent_bps: 1_000,
        provider: listing.provider,
        handle: listing.handle.clone(),
        dk: listing.key.dk.clone(),
    }
}

#[test]
fn service_urls_read_the_config_lists() {
    let document = json!({
        "extensions": {"proxy_delegation_v1": {
            "verifier_api_urls": ["https://verifier.example"],
            "proof_rpc_urls": ["https://rpc-a.example", "https://rpc-b.example"],
        }}
    });
    assert_eq!(
        proxy_service_urls(document.to_string().into_bytes()).unwrap(),
        Some(ApiProxyServiceUrls {
            verifier_api_urls: vec!["https://verifier.example".to_owned()],
            proof_rpc_urls: vec![
                "https://rpc-a.example".to_owned(),
                "https://rpc-b.example".to_owned()
            ],
        })
    );
    assert_eq!(proxy_service_urls(b"{}".to_vec()).unwrap(), None);
    assert!(proxy_service_urls(b"[".to_vec()).is_err());
}

#[test]
fn the_registry_downloads_page_by_page_into_a_cache_for_its_chain() {
    pin_regtest();
    assert_eq!(
        proxy_registry_page_path(2),
        "/shielded-vote/v1/delegates?start_after=2&limit=1000"
    );
    let entries = registry();
    assert_eq!(
        proxy_registry_next_start_after(0, 200, page_body(&entries[..2], 2)).unwrap(),
        Some(2)
    );
    assert_eq!(
        proxy_registry_next_start_after(2, 200, page_body(&entries[2..], 0)).unwrap(),
        None
    );
    assert!(proxy_registry_next_start_after(0, 503, page_body(&entries, 0)).is_err());
    let cache = build_proxy_registry_cache(
        NETWORK.to_owned(),
        vec![ApiRegistryPage {
            start_after: 0,
            body: page_body(&entries, 0),
        }],
    )
    .unwrap();
    assert_eq!(cache.entries, 4);
    assert_eq!(cache.json, cache_json());

    // A cache stored for another chain never backs a view.
    let other = cache.json.replace(CHAIN_ID, "zvote-1");
    assert!(proxy_browse(ApiProxyRegistryView {
        registry_cache: other,
        ..view()
    })
    .is_err());
}

#[test]
fn the_newest_pinned_wallet_list_is_kept() {
    pin_regtest();
    let resolve = |document: Vec<u8>, stored: Option<Vec<u8>>| {
        resolve_proxy_wallet_list(NETWORK.to_owned(), document, stored).unwrap()
    };
    let first = resolve(signed_list(1), None);
    assert_eq!(
        (first.update, first.version),
        (ApiWalletListUpdate::Adopted, Some(1))
    );
    let same = resolve(signed_list(1), Some(signed_list(1)));
    assert_eq!(same.update, ApiWalletListUpdate::Unchanged);
    let newer = resolve(signed_list(2), Some(signed_list(1)));
    assert_eq!(
        (newer.update, newer.version),
        (ApiWalletListUpdate::Adopted, Some(2))
    );
    let older = resolve(signed_list(1), Some(signed_list(2)));
    assert_eq!(
        (older.update, older.version, older.detail.as_deref()),
        (ApiWalletListUpdate::Older, Some(2), Some("version 1"))
    );
    let mut edited = wallet_list(2);
    edited.delegates.pop();
    let conflicting = resolve(
        list_document(&edited, &list_signer(), LIST_KEY_ID),
        Some(signed_list(2)),
    );
    assert_eq!(conflicting.update, ApiWalletListUpdate::ConflictingPayload);

    // Another key's signature never counts, even under the pinned key id.
    let forged = resolve(
        list_document(&wallet_list(3), &SigningKey::from([8; 32]), LIST_KEY_ID),
        Some(signed_list(2)),
    );
    assert_eq!(
        (forged.update, forged.version, forged.detail.as_deref()),
        (
            ApiWalletListUpdate::Rejected,
            Some(2),
            Some("NoPinnedSignature")
        )
    );
    // A stored list that no longer verifies counts as none.
    let replaced = resolve(signed_list(1), Some(b"{}".to_vec()));
    assert_eq!(replaced.update, ApiWalletListUpdate::Adopted);
}

#[test]
fn mainnet_and_testnet_pin_only_their_compiled_keys() {
    pin_regtest();
    for (network, (key_id, _)) in [("main", MAIN_LIST_KEY), ("test", STAGE_LIST_KEY)] {
        let pin = wallet_list_pin(network).unwrap();
        assert_eq!(pin.wallet_id, "vizor");
        assert_eq!(pin.keys.len(), 1);
        assert_eq!(pin.keys[0].key_id, key_id);
        // The regtest harness's key never signs a public network's list.
        let mut list = wallet_list(1);
        list.chain_id = pin.chain_id.clone();
        let resolution = resolve_proxy_wallet_list(
            network.to_owned(),
            list_document(&list, &list_signer(), key_id),
            None,
        )
        .unwrap();
        assert_eq!(
            resolution.update,
            ApiWalletListUpdate::Rejected,
            "{network}"
        );
    }
    assert_eq!(wallet_list_pin("main").unwrap().chain_id, "zvote-1");
    assert_eq!(wallet_list_pin("test").unwrap().chain_id, "svote-1");
    assert!(configure_regtest_wallet_list_key(
        LIST_KEY_ID.to_owned(),
        BASE64.encode(SigningKey::from([8; 32]).verification_key().to_bytes()),
    )
    .is_err());
}

#[test]
fn browse_shows_the_list_rows_in_list_order_with_their_content() {
    let browse = proxy_browse(view()).unwrap();
    assert!(!browse.list_unavailable);
    let rows: Vec<_> = browse
        .listed
        .iter()
        .map(|listing| {
            (
                listing.index,
                listing.handle.as_str(),
                listing.reviewed,
                listing.status,
            )
        })
        .collect();
    // Only an active entry that matches its row shows as reviewed.
    assert_eq!(
        rows,
        [
            (1, "alice", true, DelegateEntryStatus::Active),
            (2, "bob", false, DelegateEntryStatus::Suspended),
            (3, "carol", false, DelegateEntryStatus::Retired),
        ]
    );
    let alice = &browse.listed[0];
    assert_eq!(alice.provider, ProxyDelegateProvider::X);
    assert_eq!(alice.display_name.as_deref(), Some("Delegate 1"));
    assert_eq!(alice.picture.as_deref(), Some(picture().as_slice()));
    assert_eq!(alice.key.dk, dk(1).encode());
    assert_eq!(alice.key.fingerprint, dk(1).fingerprint().to_string());

    assert_eq!(
        proxy_wallet_list_picture(NETWORK.to_owned(), signed_list(1), 2),
        Some(picture())
    );
    assert_eq!(
        proxy_wallet_list_picture(NETWORK.to_owned(), signed_list(1), 21),
        None
    );
}

#[test]
fn search_finds_a_handle_in_the_cache_labelled_for_its_round() {
    let found = search_proxy_delegates(view(), "alice".to_owned()).unwrap();
    assert_eq!(found.len(), 1);
    assert_eq!((found[0].index, found[0].reviewed), (1, true));

    let new = &search_proxy_delegates(view(), "a1ice".to_owned()).unwrap()[0];
    assert_eq!((new.index, new.reviewed), (21, false));
    assert!(new.new_this_round);
}

#[test]
fn paste_finds_a_delegate_or_says_why_not() {
    let lookup = |text: String| lookup_proxy_delegate(view(), text).unwrap();
    let found = lookup(dk(1).encode());
    assert_eq!(found.kind, ApiDelegateLookupKind::Found);
    let listing = found.listing.unwrap();
    assert_eq!((listing.index, listing.handle.as_str()), (1, "alice"));
    let unrecognized = lookup("hello".to_owned());
    assert_eq!(
        (unrecognized.kind, unrecognized.listing),
        (ApiDelegateLookupKind::Unrecognized, None)
    );
    let not_found = lookup(dk(99).encode());
    assert_eq!(
        (not_found.kind, not_found.listing),
        (ApiDelegateLookupKind::NotFound, None)
    );
}

#[test]
fn the_pre_proving_check_gives_each_choice_its_verdict_and_listing() {
    let view = view();
    let alice = choice(&proxy_browse(view.clone()).unwrap().listed[0]);
    // Entry 21, new this round, and entry 30, proven absent.
    let new = ProxyDelegateChoice {
        delegate_index: 21,
        handle: "a1ice".to_owned(),
        dk: dk(21).encode(),
        ..alice.clone()
    };
    let absent = ProxyDelegateChoice {
        delegate_index: 30,
        ..alice.clone()
    };
    let confirmed = check_proxy_delegates(
        NETWORK.to_owned(),
        view.wallet_list,
        view.first_new_index,
        ProxyAllocationRequest {
            round_id: ROUND_ID.to_owned(),
            choices: vec![alice, new, absent],
        },
        [1, 21, 30].map(entry_proof).to_vec(),
    );
    assert_eq!(
        confirmed
            .iter()
            .map(|confirmed| confirmed.check)
            .collect::<Vec<_>>(),
        [
            DelegateCheck::Ok,
            DelegateCheck::Ok,
            DelegateCheck::NotFound
        ]
    );
    // The listing comes from the proven entry, labelled by the list and
    // the round.
    let alice = confirmed[0].listing.as_ref().unwrap();
    assert!(alice.reviewed && !alice.new_this_round);
    let new = confirmed[1].listing.as_ref().unwrap();
    assert!(!new.reviewed && new.new_this_round);
    assert!(confirmed[2].listing.is_none());
}
