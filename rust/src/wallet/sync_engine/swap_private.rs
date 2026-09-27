//! Experimental receiver → Enhance PIR → verified wallet insertion.
//! All chain acceptance and note mutation stays in the wallet library.
use super::{SyncError, WalletDatabase};
use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};
use futures::{Future, FutureExt, StreamExt};
use orchard::tree::{MerkleHashOrchard, MerklePath};
use receiver_directory::Receiver;
use receiver_pir::{http::HttpClient, AcceptedCoverage};
use std::{num::NonZeroU32, time::Duration};
use zakura_pir_enhance::wallet::{self as enhance_wallet, Acceptance, PreparedWork};
use zakura_pir_enhance::{
    transport::{Method, PendingClient, Request, ResponseBody, Transport},
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

// This build only talks to explicit local SSH tunnels. Never follow service redirects.
const RECEIVER_ORIGIN: &str = "http://127.0.0.1:18380";
const ENHANCE_ORIGIN: &str = "http://127.0.0.1:18280";
struct Http(reqwest::Client);
impl Transport for Http {
    async fn execute(&self, request: Request) -> Result<ResponseBody, ClientError> {
        let mut body = request.response_body();
        let method = match request.method {
            Method::Get => reqwest::Method::GET,
            Method::Post => reqwest::Method::POST,
        };
        // Manifest-provided session URLs must stay inside the selected tunnel too.
        let url =
            url::Url::parse(&request.url).map_err(|e| ClientError::Transport(e.to_string()))?;
        if url.scheme() != "http"
            || url.host_str() != Some("127.0.0.1")
            || url.port() != Some(18280)
        {
            return Err(ClientError::Transport(
                "Enhance route escaped the POC tunnel".into(),
            ));
        }
        let mut response = self
            .0
            .request(method, url)
            .body(request.body)
            .send()
            .await
            .map_err(|e| ClientError::Transport(e.to_string()))?;
        if !response.status().is_success() {
            return Err(ClientError::HttpStatus(response.status().as_u16()));
        }
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|e| ClientError::Transport(e.to_string()))?
        {
            body.extend(&chunk)?;
        }
        Ok(body.finish())
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
    if !crate::wallet::swap_receiving::private_recovery_enabled() {
        return Ok(());
    }
    if network != WalletNetwork::Main {
        return Err(SyncError::db("Private swap POC requires mainnet"));
    }
    if crate::network_privacy::is_tor_desired() {
        return Err(SyncError::net(
            "Private swap POC SSH tunnels require Tor off",
        ));
    }
    // A Tor toggle or cancellation drops the entire phase, including pending HTTP reads.
    let lease = crate::network_privacy::DirectRouteLease::new();
    let phase = run_inner(db, network).map(|r| r.map_err(std::io::Error::other));
    futures::pin_mut!(phase);
    let routed = futures::future::poll_fn(|cx| lease.poll(cx, |cx| phase.as_mut().poll(cx)));
    tokio::select! {
        biased;
        _=super::watch_for_exit(should_exit)=>Ok(()),
        result=routed=>result.map_err(|e|SyncError::net(format!("Private swap recovery pending: {e}"))),
    }
}
async fn run_inner(db: &mut WalletDatabase, network: WalletNetwork) -> Result<(), String> {
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
    let http = reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(60))
        .build()
        .map_err(error)?;
    let transport = Http(http.clone());
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
    let prepared = PreparedWork::new(
        db.transaction_enhancement_work()
            .map_err(error)?
            .into_iter()
            .filter_map(|w| match w {
                TransactionEnhancementWork::Private(w) => Some(w),
                _ => None,
            }),
    );
    for requests in prepared.batches_by_tx_and_row().into_values() {
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
    if !prepared.rediscover.is_empty() || prepared.suspended > 0 {
        log::warn!("swap_private: outgoing enhancement still needs local context; keeping it private and pending");
    }
    let advertised = HttpClient::fetch_manifest(RECEIVER_ORIGIN, &http)
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
    let client = HttpClient::connect(RECEIVER_ORIGIN, http.clone(), accepted)
        .await
        .map_err(error)?;
    let anchor = ChainAnchor {
        height,
        hash: hash.0,
    };
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
            if db
                .swap_directory_check(account, key.key_id())
                .map_err(error)?
                != Some(anchor)
            {
                work.push((account, key));
            }
        }
    }
    if work.is_empty() {
        return Ok(());
    }
    if through.height < height || through.height - height > 100 {
        return Err("Directory witness publication is stale; refresh the test service".into());
    }
    // Download the same proof file before any receiver lookups, including when no key matches.
    let witnesses = client.witnesses().await.map_err(error)?;
    let mut applied = 0;
    for (account, key) in work {
        let receiver =
            Receiver::from_bytes(key.receiver().to_raw_address_bytes()).map_err(error)?;
        let payments = client
            .lookup(receiver, NonZeroU32::new(32).unwrap(), accepted)
            .await
            .map_err(error)?;
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
            applied += 1;
        }
        with_wallet_db_write_lock("swap_private.checked", || {
            db.mark_swap_directory_checked(account, key.key_id(), anchor)
                .map_err(error)
        })?;
    }
    // Paid receive indices can extend the lookahead. The next sync checks the new keys.
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
        let http = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(60))
            .build()
            .unwrap();
        let client = HttpClient::connect(RECEIVER_ORIGIN, http.clone(), accepted)
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
        let transport = Http(http);
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
