//! Experimental receiver → Enhance PIR → verified wallet insertion.
//! All chain acceptance and note mutation stays in the wallet library.
use super::enhancement::transport::{RoutedHttpError, RoutedTransport};
use super::{SyncError, WalletDatabase};
use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};
use futures::StreamExt;
use orchard::tree::{MerkleHashOrchard, MerklePath};
use receiver_directory::Receiver;
use receiver_pir::{
    transport::{DirectoryClient, Transport as ReceiverTransport},
    AcceptedCoverage,
};
use std::num::NonZeroU32;
use zakura_pir_enhance::wallet::{self as enhance_wallet, Acceptance, PreparedWork};
use zakura_pir_enhance::{
    transport::{PendingClient, Request, ResponseBody, Transport},
    ClientError, ClientResourceLimits,
};
use zakura_swap_receiving::{lifecycle::ChainAnchor, recovery::EncryptedNote};
use zcash_client_backend::data_api::enhance_pir::{
    EnhancePirRead, EnhancePirWrite, TransactionEnhancementWork,
};
use zcash_client_backend::data_api::{Account as _, AccountSource, WalletRead};
use zcash_client_sqlite::wallet::swap_receiving::{PaymentApplication, PendingPayment};
use zcash_primitives::{block::BlockHash, transaction::TxId};
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
pub(crate) struct SwapTransport<'a, F>(RoutedTransport<'a, F>);
impl<'a, F> SwapTransport<'a, F> {
    pub(crate) fn new(should_exit: &'a F) -> Self {
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

pub(super) async fn run(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    if network != WalletNetwork::Main || cfg!(ironwood_masquerade) {
        return Ok(());
    }
    let Some(tip) = db
        .block_fully_scanned()
        .map_err(|e| SyncError::db(e.to_string()))?
    else {
        return Ok(());
    };
    let through = ChainAnchor {
        height: tip.block_height(),
        hash: tip.block_hash().0,
    };
    let started = std::time::Instant::now();
    let phase = async {
        let result = async {
            loop {
                let before: Vec<_> = discovery_work(db, through)?
                    .into_iter()
                    .map(|(account, key)| (account, key.key_id()))
                    .collect();
                run_inner(db, network, should_exit).await?;
                with_wallet_db_write_lock("swap_private.prune", || {
                    crate::wallet::swap_receiving::finish_nullifier_recovery(db, through)
                })?;
                // A payment at the window edge adds more keys. Finish checking
                // them in this sync before announcing a complete restore.
                let after: Vec<_> = discovery_work(db, through)?
                    .into_iter()
                    .map(|(account, key)| (account, key.key_id()))
                    .collect();
                if after.is_empty() {
                    return Ok::<(), String>(());
                }
                if after == before {
                    return Err("Swap recovery needs more scanning or a newer publication".into());
                }
            }
        }
        .await;
        log::info!(
            "pir_metric component=recovery stage=total elapsed_us={} ok={}",
            started.elapsed().as_micros(),
            result.is_ok()
        );
        result.map_err(std::io::Error::other)
    };
    tokio::select! {
        biased;
        _=super::watch_for_exit(should_exit)=>Ok(()),
        result=phase=>result.map_err(|e|SyncError::net(format!("Private swap recovery pending: {e}"))),
    }
}

fn discovery_work(
    db: &mut WalletDatabase,
    through: ChainAnchor,
) -> Result<
    Vec<(
        zcash_client_sqlite::AccountUuid,
        zcash_client_sqlite::wallet::swap_receiving::RegisteredKey,
    )>,
    String,
> {
    let mut work = Vec::new();
    for account in db.get_account_ids().map_err(error)? {
        let details = db
            .get_account(account)
            .map_err(error)?
            .ok_or("Account disappeared")?;
        if !matches!(details.source(), AccountSource::Derived { .. })
            || crate::wallet::keys::hardware_signer_kind(details.source()).is_some()
        {
            continue;
        }
        for key in db.get_swap_receiving_keys(account).map_err(error)? {
            let target = with_wallet_db_write_lock("swap_private.target", || {
                db.prepare_swap_recovery_target(account, key.key_id(), through)
                    .map_err(error)
            })?;
            if let Some(target) = target {
                // Closeout requires a directory check even if local scanning found
                // the receipt. Its saved target does not move with the chain tip.
                if db
                    .swap_directory_check(account, key.key_id())
                    .map_err(error)?
                    .is_none_or(|checked| checked.height < target.height)
                    || !db
                        .pending_swap_payments(account, key.key_id())
                        .map_err(error)?
                        .is_empty()
                {
                    work.push((account, key));
                }
            }
        }
    }
    Ok(work)
}

/// Connects to a directory publication bound to locally accepted block history.
pub(crate) async fn receiver_client<T: ReceiverTransport>(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    http: T,
) -> Result<(DirectoryClient<T>, AcceptedCoverage, ChainAnchor), String> {
    let advertised = DirectoryClient::fetch_manifest(RECEIVER_ORIGIN, &http)
        .await
        .map_err(error)?;
    let height = BlockHeight::from(advertised.directory.end_height);
    let hash = db
        .get_block_hash(height)
        .map_err(error)?
        .ok_or("Directory anchor has not been scanned")?;
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
        height: height.into(),
        hash: hash.0,
    };
    let client = DirectoryClient::connect(RECEIVER_ORIGIN, http, accepted)
        .await
        .map_err(error)?;
    let anchor = ChainAnchor {
        height,
        hash: hash.0,
    };
    Ok((client, accepted, anchor))
}

async fn run_inner(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    should_exit: &impl Fn() -> bool,
) -> Result<(), String> {
    let Some(tip) = db.block_fully_scanned().map_err(error)? else {
        return Ok(());
    };
    if Some(tip.block_height()) != db.chain_height().map_err(error)? {
        return Ok(());
    }
    let through = ChainAnchor {
        height: tip.block_height(),
        hash: tip.block_hash().0,
    };
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
    super::swap_refund_status::reconcile(db, through.height, should_exit).await?;
    if batches.is_empty() && discovery_work(db, through)?.is_empty() {
        log::info!("swap_private: recovery covered locally; no PIR requests");
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
    super::swap_refund_status::reconcile(db, through.height, should_exit).await?;
    // Outgoing rediscovery needs local compact context, not another PIR request.
    // Keep its durable queue without retrying it on the network every block.
    let mut work = discovery_work(db, through)?;
    if work.is_empty() {
        return Ok(());
    }
    let (client, accepted, anchor) = receiver_client(db, network, &transport).await?;
    let height = anchor.height;
    let mut unchecked = Vec::new();
    for (account, key) in work.drain(..) {
        if db
            .swap_recovery_target(account, key.key_id())
            .map_err(error)?
            .is_some_and(|target| target.height <= height)
            && db
                .swap_directory_check(account, key.key_id())
                .map_err(error)?
                != Some(anchor)
        {
            unchecked.push((account, key));
        }
    }
    let work = unchecked;
    if work.is_empty() {
        return Err("Directory publication has not reached the swap recovery target".into());
    }
    if through.height < height || through.height - height > 100 {
        return Err("Directory witness publication is stale; refresh the test service".into());
    }
    // Download the same proof file before any receiver lookups, including when no key matches.
    log::info!(
        "pir_metric component=recovery stage=work receivers={}",
        work.len()
    );
    let witnesses = client.witnesses().await.map_err(error)?;
    let mut applied = 0;
    for (account, key) in work {
        let receiver =
            Receiver::from_bytes(key.receiver().to_raw_address_bytes()).map_err(error)?;
        let lookup_started = std::time::Instant::now();
        let payments = client
            .lookup(receiver, NonZeroU32::new(32).unwrap(), accepted)
            .await
            .map_err(error)?;
        log::info!(
            "pir_metric component=receiver stage=lookup elapsed_us={} payments={}",
            lookup_started.elapsed().as_micros(),
            payments.len()
        );
        for payment in payments {
            // Persist only authenticated full ciphertext. A failed stage is retried from its durable queue.
            let stream = enhance
                .query_batch(&transport, [payment.position])
                .map_err(error)?;
            futures::pin_mut!(stream);
            let record = stream
                .next()
                .await
                .ok_or("Missing Enhance result")?
                .record
                .map_err(error)?;
            let candidate = PendingPayment {
                txid: TxId::from_bytes(payment.txid),
                action_index: payment.action_index,
                height: payment.height.into(),
                block_hash: BlockHash(payment.block_hash),
                tx_index: payment.tx_index.try_into().map_err(error)?,
                position: payment.position.try_into().map_err(error)?,
                encrypted_note: EncryptedNote::from_parts(
                    payment.action_nullifier,
                    payment.cmx,
                    payment.ephemeral_key,
                    payment.ciphertext_prefix,
                    record.enc_ciphertext_suffix(),
                ),
            };
            let apply_started = std::time::Instant::now();
            let raw_path = witnesses
                .path(candidate.position, payment.cmx)
                .map_err(error)?;
            let path = MerklePath::from_parts(
                candidate.position,
                raw_path.map(|h| MerkleHashOrchard::from_bytes(&h).unwrap()),
            );
            let result =
                with_wallet_db_write_lock("swap_private.apply", || -> Result<_, String> {
                    db.queue_swap_payment(account, key.key_id(), &candidate)
                        .map_err(error)?;
                    db.apply_pending_swap_payment(
                        account,
                        key.key_id(),
                        &candidate,
                        through,
                        Some((anchor, &path)),
                    )
                    .map_err(error)
                })?;
            if result != PaymentApplication::Applied {
                return Err(format!("Payment remains queued: {result:?}"));
            }
            log::info!(
                "pir_metric component=recovery stage=validate_insert elapsed_us={}",
                apply_started.elapsed().as_micros()
            );
            applied += 1;
        }
        with_wallet_db_write_lock("swap_private.checked", || {
            db.mark_swap_directory_checked(account, key.key_id(), anchor)
                .map_err(error)
        })?;
    }
    // The caller repeats discovery if these payments extend the receive window.
    with_wallet_db_write_lock("swap_private.lookahead", || {
        crate::wallet::swap_receiving::maintain_recovery(db, network)
    })?;
    log::info!(
        "swap_private: directory checked at {} with {applied} verified payments",
        u32::from(height)
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use zakura_pir_enhance::{AcceptedAnchor, GenerationAcceptance};

    #[test]
    fn restore_checks_extended_window_without_rechecking_completed_keys() {
        use crate::wallet::{
            db::{open_wallet_db_with_timeout, WALLET_DB_BUSY_TIMEOUT},
            keys,
        };
        use secrecy::SecretVec;
        use zakura_swap_receiving::{KeyId, Purpose};
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
        let through = ChainAnchor {
            height,
            hash: [0; 32],
        };
        db.enable_private_swap_recovery(account).unwrap();
        db.maintain_swap_receive_lookahead(account, 50, height)
            .unwrap();
        assert!(!crate::api::sync::enhance_pir_enabled());
        assert!(!crate::api::sync::near_swap_privacy_enabled());
        let work = discovery_work(&mut db, through).unwrap();
        assert_eq!(work.len(), 50);
        for (account, key) in work {
            db.mark_swap_directory_checked(account, key.key_id(), through)
                .unwrap();
        }
        assert!(discovery_work(&mut db, through).unwrap().is_empty());

        // Model the registry advancement after a verified payment at the edge.
        // The library tests exercise the actual compact note decryption.
        db.recover_swap_receiving_key(account, KeyId::new(Purpose::Receive, 49), height)
            .unwrap();
        db.maintain_swap_receive_lookahead(account, 50, height)
            .unwrap();
        let work = discovery_work(&mut db, through).unwrap();
        assert_eq!(work.len(), 50);
        assert!(work.iter().all(|(_, key)| key.key_id().index() >= 50));
        for (account, key) in work {
            db.mark_swap_directory_checked(account, key.key_id(), through)
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
        assert!(discovery_work(&mut db, later).unwrap().is_empty());
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
