//! Experimental receiver → Enhance PIR → verified wallet insertion.
//! All chain acceptance and note mutation stays in the wallet library.
use super::enhancement::transport::{RoutedHttpError, RoutedTransport};
use super::WalletDatabase;
use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};
use futures::StreamExt;
use receiver_directory::Receiver;
use receiver_pir::{
    transport::{DirectoryClient, Transport as ReceiverTransport},
    AcceptedCoverage,
};
use std::{collections::BTreeMap, num::NonZeroU32};
use zakura_pir_enhance::wallet::{self as enhance_wallet, Acceptance, PreparedWork};
use zakura_pir_enhance::{
    transport::{PendingClient, Request, ResponseBody, Transport},
    ClientError, ClientResourceLimits,
};
use zakura_swap_receiving::lifecycle::ChainAnchor;
use zcash_client_backend::data_api::enhance_pir::{
    EnhancePirRead, EnhancePirWrite, TransactionEnhancementWork,
};
use zcash_client_backend::data_api::WalletRead;
use zcash_client_sqlite::wallet::swap_receiving::{
    DirectoryPayment, DiscoveryWork, PaymentApplication,
};
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

// Use explicit HTTPS origins and never follow service redirects.
const RECEIVER_ORIGIN: &str = "https://161-35-182-172.sslip.io";
const ENHANCE_ORIGIN: &str = "https://enhance-pir.valargroup.dev";
fn allowed_enhance_route(url: &url::Url) -> bool {
    url.scheme() == "https"
        && url.host_str() == Some("enhance-pir.valargroup.dev")
        && url.port_or_known_default() == Some(443)
        && url.username().is_empty()
        && url.password().is_none()
}
/// Both swap services use the same Tor-aware transport as ordinary Enhance PIR.
struct SwapTransport<'a, F>(RoutedTransport<'a, F>);
impl<'a, F> SwapTransport<'a, F> {
    fn new(should_exit: &'a F) -> Self {
        Self(RoutedTransport::new(should_exit))
    }
}
impl<F: Fn() -> bool> Transport for SwapTransport<'_, F> {
    async fn execute(&self, request: Request) -> Result<ResponseBody, ClientError> {
        let url = url::Url::parse(&request.url)
            .map_err(|_| ClientError::Transport("Invalid Enhance URL".into()))?;
        if !allowed_enhance_route(&url) {
            return Err(ClientError::Transport(
                "Enhance route escaped the selected HTTPS origin".into(),
            ));
        }
        self.0.execute(request).await
    }
}
fn receiver_error(error: RoutedHttpError) -> receiver_pir::Error {
    match error {
        RoutedHttpError::HttpStatus(409 | 410) => receiver_pir::Error::Revision,
        RoutedHttpError::HttpStatus(status) => {
            receiver_pir::Error::Transport(format!("HTTP {status}"))
        }
        RoutedHttpError::Cancelled => receiver_pir::Error::Transport("Cancelled".into()),
        RoutedHttpError::Failed(error) => receiver_pir::Error::Transport(error.to_string()),
    }
}
impl<F: Fn() -> bool> ReceiverTransport for SwapTransport<'_, F> {
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, receiver_pir::Error> {
        self.0
            .bytes(http::Method::GET, url, vec![], limit)
            .await
            .map_err(receiver_error)
    }
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, receiver_pir::Error> {
        self.0
            .bytes(http::Method::POST, url, body, limit)
            .await
            .map_err(receiver_error)
    }
}
fn error(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Polls restored refunds and runs pending restore sweeps. Failures are logged and
/// retried on the next sync; ordinary sync never waits for the directory.
pub(super) async fn run(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    should_exit: &impl Fn() -> bool,
) {
    if network != WalletNetwork::Main || cfg!(ironwood_masquerade) {
        return;
    }
    let tip = match db.block_fully_scanned() {
        Ok(Some(tip)) => tip,
        Ok(None) => return,
        Err(e) => return log::warn!("Swap recovery deferred: {e}"),
    };
    let through = ChainAnchor {
        height: tip.block_height(),
        hash: tip.block_hash().0,
    };
    let started = std::time::Instant::now();
    let phase = async {
        let result = async {
            run_inner(db, network, through, should_exit).await?;
            with_wallet_db_write_lock("swap_private.prune", || {
                crate::wallet::swap_receiving::finish_nullifier_recovery(db, through)
            })?;
            for account in crate::wallet::swap_receiving::software_accounts(db)? {
                if db
                    .swap_history_pending(account, through.height)
                    .map_err(error)?
                {
                    return Err("restore sweeps remain pending".to_owned());
                }
            }
            Ok::<(), String>(())
        }
        .await;
        log::info!(
            "pir_metric component=recovery stage=total elapsed_us={} ok={}",
            started.elapsed().as_micros(),
            result.is_ok()
        );
        result
    };
    tokio::select! {
        biased;
        _ = super::watch_for_exit(should_exit) => {}
        result = phase => {
            if let Err(e) = result {
                log::warn!("Swap recovery deferred: {e}");
            }
        }
    }
}

fn discovery_work(
    db: &mut WalletDatabase,
    through: ChainAnchor,
) -> Result<
    (
        Vec<(zcash_client_sqlite::AccountUuid, DiscoveryWork)>,
        usize,
    ),
    String,
> {
    let mut work = Vec::new();
    let mut remaining = 0;
    let now = crate::wallet::swap_receiving::receive::now()?;
    for account in crate::wallet::swap_receiving::software_accounts(db)? {
        let batch = with_wallet_db_write_lock("swap_private.discovery", || {
            db.prepare_swap_discovery_batch(account, through, now, NonZeroU32::new(64).unwrap())
                .map_err(error)
        })?;
        remaining += batch.remaining_lookups;
        work.extend(batch.work.into_iter().map(|key| (account, key)));
    }
    Ok((work, remaining))
}

/// Connects to a directory publication bound to locally accepted block history.
async fn receiver_client<T: ReceiverTransport>(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    http: T,
    through: ChainAnchor,
    remaining_lookups: usize,
) -> Result<(DirectoryClient<T>, AcceptedCoverage, ChainAnchor), String> {
    let advertised = DirectoryClient::fetch_manifest(RECEIVER_ORIGIN, &http)
        .await
        .map_err(error)?;
    let anchor = db
        .swap_publication_anchor(BlockHeight::from(advertised.directory.end_height), through)
        .map_err(error)?;
    let activation = network
        .activation_height(NetworkUpgrade::Nu6_3)
        .ok_or("Ironwood inactive")?;
    let mut genesis: [u8; 32] =
        hex::decode("00040fe8ec8471911baa1db1266ea15dd06b4a8a5c453883c000b031973dce08")
            .unwrap()
            .try_into()
            .unwrap();
    genesis.reverse();
    let accepted = AcceptedCoverage {
        genesis,
        required_start: activation.into(),
        height: anchor.height.into(),
        hash: anchor.hash,
    };
    let client = DirectoryClient::connect_manifest(
        RECEIVER_ORIGIN,
        http,
        accepted,
        advertised,
        remaining_lookups,
    )
    .await
    .map_err(error)?;
    Ok((client, accepted, anchor))
}

/// A directory payment as the wallet library takes it.
fn directory_payment(payment: receiver_directory::Payment) -> DirectoryPayment {
    DirectoryPayment {
        height: payment.height,
        block_hash: payment.block_hash,
        txid: payment.txid,
        tx_index: payment.tx_index,
        action_index: payment.action_index,
        position: payment.position,
        action_nullifier: payment.action_nullifier,
        cmx: payment.cmx,
        ephemeral_key: payment.ephemeral_key,
        ciphertext_prefix: payment.ciphertext_prefix,
    }
}

/// Runs recovery at `through`, the fully scanned block, if it is also the chain tip.
async fn run_inner(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    through: ChainAnchor,
    should_exit: &impl Fn() -> bool,
) -> Result<(), String> {
    if Some(through.height) != db.chain_height().map_err(error)? {
        return Ok(());
    }
    // The exception covers receiver discovery and its matching note data only.
    // Ordinary memo enhancement still follows the general Private queries setting.
    let prepared = PreparedWork::new(
        db.transaction_enhancement_work()
            .map_err(error)?
            .into_iter()
            .filter_map(|w| match w {
                TransactionEnhancementWork::Private(w)
                    if crate::api::sync::enhance_pir_enabled() =>
                {
                    Some(w)
                }
                _ => None,
            }),
    );
    let batches = prepared.batches_by_tx_and_row();
    super::swap_refund_status::reconcile(db, should_exit).await?;
    if batches.is_empty() && discovery_work(db, through)?.0.is_empty() {
        return Ok(());
    }
    let transport = SwapTransport::new(should_exit);
    let pending = PendingClient::fetch(&transport, ENHANCE_ORIGIN)
        .await
        .map_err(error)?;
    let acceptance = match enhance_wallet::acceptance(
        db,
        pending.manifest(),
        &network,
        ClientResourceLimits::with_cache(32768, 2),
    )
    .map_err(error)?
    .map_err(error)?
    {
        Acceptance::Accepted(a) => a,
        Acceptance::WaitingForScanning => return Err("Enhance anchor has not been scanned".into()),
        Acceptance::Mismatch => return Err("Enhance anchor differs from the accepted chain".into()),
    };
    let mut enhance = pending.accept(&acceptance).map_err(error)?;
    for requests in batches.into_values() {
        let reply = enhance
            .query_row_requests(&transport, &requests)
            .await
            .map_err(error)?;
        with_wallet_db_write_lock("swap_private.enhance", || {
            db.apply_ironwood_enhance_records(&reply.slots)
                .map_err(error)
        })?;
    }
    // Incoming funding memos can now register refund keys before directory lookups.
    with_wallet_db_write_lock("swap_private.memos", || {
        crate::wallet::swap_receiving::maintain_recovery(db, network)
    })?;
    let (mut work, remaining) = discovery_work(db, through)?;
    if work.is_empty() {
        return Ok(());
    }
    let (mut client, accepted, anchor) =
        receiver_client(db, network, &transport, through, remaining).await?;
    // Both modes fetch the same common proofs once for the entire revision.
    let witnesses = client.witnesses().await.map_err(error)?;
    let mut failures = 0usize;
    loop {
        for (account, work_item) in work {
            if should_exit() {
                return Ok(());
            }
            let now = crate::wallet::swap_receiving::receive::now()?;
            let result = async {
                let key = work_item.key;
                with_wallet_db_write_lock("swap_private.attempt", || {
                    db.begin_swap_discovery_attempt(account, key, anchor, now)
                        .map_err(error)
                })?;
                if work_item.lookup.is_none() {
                    let receiver = Receiver::from_bytes(work_item.receiver).map_err(error)?;
                    let payments: Vec<_> = client
                        .lookup(receiver, NonZeroU32::new(32).unwrap(), accepted)
                        .await
                        .map_err(error)?
                        .into_iter()
                        .map(directory_payment)
                        .collect();
                    let positions = db
                        .swap_note_data_needed(account, key, &payments)
                        .map_err(error)?;
                    // Enhance groups these positions into shared row requests internally.
                    let stream = enhance.query_batch(&transport, positions).map_err(error)?;
                    futures::pin_mut!(stream);
                    let mut note_data = BTreeMap::new();
                    while let Some(result) = stream.next().await {
                        let record = result.record.map_err(error)?;
                        note_data.insert(result.position, *record.enc_ciphertext_suffix());
                    }
                    with_wallet_db_write_lock("swap_private.queue", || {
                        db.queue_swap_directory_lookup(account, key, anchor, &payments, &note_data)
                            .map_err(error)
                    })?;
                }
                let applied = with_wallet_db_write_lock("swap_private.apply", || {
                    db.apply_swap_sweep(account, key, through, anchor, |position, cmx| {
                        witnesses.path(position, cmx).ok()
                    })
                    .map_err(error)
                })?;
                if applied != PaymentApplication::Applied {
                    return Err(format!("Payment remains queued: {applied:?}"));
                }
                Ok::<(), String>(())
            }
            .await;
            if let Err(e) = result {
                failures += 1;
                log::warn!("Private swap recovery work deferred: {e}");
            }
        }
        with_wallet_db_write_lock("swap_private.lookahead", || {
            crate::wallet::swap_receiving::maintain_recovery(db, network)
        })?;
        let (next, remaining) = discovery_work(db, through)?;
        if next.is_empty() {
            break;
        }
        client.use_file_for_work(remaining).await.map_err(error)?;
        work = next;
    }
    if failures > 0 {
        return Err(format!("{failures} swap recovery records remain pending"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use zakura_pir_enhance::{AcceptedAnchor, GenerationAcceptance};
    use zcash_client_sqlite::wallet::swap_receiving::RECEIVE_GAP_LIMIT;

    #[test]
    fn restore_checks_extended_window_without_rechecking_completed_keys() {
        use crate::wallet::{
            db::{open_wallet_db_with_timeout, WALLET_DB_BUSY_TIMEOUT},
            keys,
        };
        use secrecy::SecretVec;
        use zcash_client_backend::data_api::WalletWrite;

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("restore.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Main;
        let height = network.activation_height(NetworkUpgrade::Nu6_3).unwrap();
        let (uuid, _) = keys::init_db_and_create_account(
            path,
            network,
            &SecretVec::new(vec![1; 32]),
            Some(height.into()),
            "restore",
        )
        .unwrap();
        let account = keys::parse_account_uuid(&uuid).unwrap();
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        db.update_chain_tip(height).unwrap();
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute(
            "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(?1,zeroblob(32),0,X'000000')",
            [u32::from(height)],
        )
        .unwrap();
        // Model completed ordinary scanning of the birthday block.
        conn.execute("DELETE FROM scan_queue", []).unwrap();
        conn.execute(
            "INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(?1,?2,10)",
            [u32::from(height), u32::from(height) + 1],
        )
        .unwrap();
        let through = ChainAnchor {
            height,
            hash: [0; 32],
        };
        db.maintain_swap_receiving(account).unwrap();
        assert!(!crate::api::sync::enhance_pir_enabled());
        assert!(!crate::api::sync::near_swap_privacy_enabled());
        let work = discovery_work(&mut db, through).unwrap().0;
        assert_eq!(work.len() as u64, RECEIVE_GAP_LIMIT);
        for (account, key) in work {
            db.queue_swap_directory_lookup(account, key.key, through, &[], &BTreeMap::new())
                .unwrap();
            db.apply_swap_sweep(account, key.key, through, through, |_, _| None)
                .unwrap();
        }
        assert!(discovery_work(&mut db, through).unwrap().0.is_empty());

        // Model the registry advancement scanning records for a payment at the edge.
        // The library tests exercise the actual compact note decryption.
        let edge = RECEIVE_GAP_LIMIT - 1;
        conn.execute(
            "UPDATE ironwood_receiving_keys SET advances_allocation = 1
             WHERE purpose = 1 AND key_index = ?1",
            [edge.to_be_bytes()],
        )
        .unwrap();
        db.maintain_swap_receiving(account).unwrap();
        let work = discovery_work(&mut db, through).unwrap().0;
        assert_eq!(work.len() as u64, RECEIVE_GAP_LIMIT);
        assert!(work.iter().all(|(_, key)| key.key.index() > edge));
        for (account, key) in work {
            db.queue_swap_directory_lookup(account, key.key, through, &[], &BTreeMap::new())
                .unwrap();
            db.apply_swap_sweep(account, key.key, through, through, |_, _| None)
                .unwrap();
        }
        drop(db);
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        let later = ChainAnchor {
            height: height + 1,
            hash: [1; 32],
        };
        conn.execute(
            "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(?1,?2,0,X'000000')",
            rusqlite::params![u32::from(later.height), later.hash],
        )
        .unwrap();
        assert!(discovery_work(&mut db, later).unwrap().0.is_empty());
    }

    #[test]
    fn enhance_routes_remain_on_the_public_tls_origin() {
        assert!(allowed_enhance_route(
            &url::Url::parse("https://enhance-pir.valargroup.dev/v1/enhance/init").unwrap()
        ));
        for route in [
            "http://enhance-pir.valargroup.dev/v1/enhance/init",
            "https://enhance-pir.valargroup.dev:8443/v1/enhance/init",
            "https://enhance-pir.valargroup.dev.example.com/v1/enhance/init",
            "https://user@enhance-pir.valargroup.dev/v1/enhance/init",
            "http://127.0.0.1:18280/v1/enhance/init",
        ] {
            assert!(
                !allowed_enhance_route(&url::Url::parse(route).unwrap()),
                "{route}"
            );
        }
    }
    /// Uses only a public zero-OVK chain fixture and independently checked RPC anchors.
    #[tokio::test]
    #[ignore = "requires the isolated PIR services and VIZOR_SWAP_PUBLIC_ANCHORS"]
    async fn public_refund_round_trips_the_vizor_dependency_graph() {
        let anchors: serde_json::Value = serde_json::from_slice(
            &std::fs::read(std::env::var("VIZOR_SWAP_PUBLIC_ANCHORS").unwrap()).unwrap(),
        )
        .unwrap();
        fn hash(v: &serde_json::Value) -> [u8; 32] {
            let mut b = hex::decode(v.as_str().unwrap()).unwrap();
            b.reverse();
            b.try_into().unwrap()
        }
        let accepted = AcceptedCoverage {
            genesis: hash(&anchors["genesis"]),
            required_start: 3428143,
            height: anchors["directory"]["height"].as_u64().unwrap() as u32,
            hash: hash(&anchors["directory"]["hash"]),
        };
        let should_exit = || false;
        let transport = SwapTransport::new(&should_exit);
        let client = DirectoryClient::connect(RECEIVER_ORIGIN, &transport, accepted)
            .await
            .unwrap();
        let proofs = client.witnesses().await.unwrap();
        assert_eq!(
            hex::encode(proofs.root),
            anchors["directory"]["root"].as_str().unwrap()
        );
        let fixture: serde_json::Value = serde_json::from_str(include_str!(
            "../../../tests/fixtures/swap-zero-ovk-action.json"
        ))
        .unwrap();
        fn field<const N: usize>(v: &serde_json::Value, k: &str) -> [u8; N] {
            hex::decode(v["action"][k].as_str().unwrap())
                .unwrap()
                .try_into()
                .unwrap()
        }
        let action = receiver_directory::extract::Action {
            cv: field(&fixture, "cv"),
            nullifier: field(&fixture, "nullifier"),
            cmx: field(&fixture, "cmx"),
            ephemeral_key: field(&fixture, "ephemeralKey"),
            enc_ciphertext: field(&fixture, "encCiphertext"),
            out_ciphertext: field(&fixture, "outCiphertext"),
        };
        let receiver = action.recover_receiver().unwrap().unwrap();
        let found = client
            .lookup(receiver, NonZeroU32::new(32).unwrap(), accepted)
            .await
            .unwrap();
        let payment = found.iter().find(|p| p.position == 610503).unwrap();
        assert_eq!(payment.height, 3496114);
        proofs.path(610503, action.cmx).unwrap();
        let pending = PendingClient::fetch(&transport, ENHANCE_ORIGIN)
            .await
            .unwrap();
        let mut display = hash(&anchors["enhance"]["hash"]);
        display.reverse();
        let acceptance = GenerationAcceptance::new(
            "main",
            3428143,
            AcceptedAnchor::new(
                anchors["enhance"]["height"].as_u64().unwrap(),
                display,
                anchors["enhance"]["records"].as_u64().unwrap(),
            ),
            ClientResourceLimits::with_cache(32768, 2),
        );
        let mut enhance = pending.accept(&acceptance).unwrap();
        let stream = enhance.query_batch(&transport, [610503]).unwrap();
        futures::pin_mut!(stream);
        let record = stream.next().await.unwrap().record.unwrap();
        assert_eq!(
            record.enc_ciphertext_suffix().as_slice(),
            &action.enc_ciphertext[52..]
        );
        println!("Vizor dependencies verified receiver PIR, full ciphertext via Enhance PIR, and common witness at position 610503");
    }
}
