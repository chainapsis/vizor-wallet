//! Restore sweeps of swap keys through the receiver directory, with the matching
//! Enhance PIR note data. The sweep's rules, chain acceptance and note mutation live
//! in `zakura_pir_receiver` and the wallet library; this module supplies Vizor's
//! routed transport, service origins, write lock and run budget.
use super::enhancement::transport::{RoutedHttpError, RoutedTransport};
use super::WalletDatabase;
use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};
use std::time::Duration;
use zakura_pir_enhance::transport::{Request, ResponseBody, Transport};
use zakura_pir_enhance::ClientError;
use zakura_pir_receiver::{
    DirectoryError, EnhanceNotes, Swept, Transport as ReceiverTransport, WriteLock, MAINNET_GENESIS,
};
use zcash_client_backend::data_api::{transparent_ledger::ChainPoint, WalletRead};
use zcash_client_sqlite::wallet::swap_receiving::Error as SwapError;

/// The receiver directory's default origin. Use explicit HTTPS origins and never follow
/// service redirects.
const DEFAULT_RECEIVER_ORIGIN: &str = "https://receiver-pir.valargroup.dev";
/// Overrides [`DEFAULT_RECEIVER_ORIGIN`], like Enhance's `VIZOR_ENHANCE_PIR_URL`.
const RECEIVER_ORIGIN_ENV: &str = "VIZOR_RECEIVER_PIR_URL";
/// Time one recovery run may take. Sweeps it does not reach wait for a later sync.
const RUN_BUDGET: Duration = Duration::from_secs(180);
/// The receiver directory's origin: [`RECEIVER_ORIGIN_ENV`], then
/// [`DEFAULT_RECEIVER_ORIGIN`].
fn receiver_origin() -> String {
    std::env::var(RECEIVER_ORIGIN_ENV).unwrap_or_else(|_| DEFAULT_RECEIVER_ORIGIN.into())
}
/// Whether `url` stays on `origin`, the configured Enhance endpoint, over HTTPS.
fn allowed_enhance_route(origin: &url::Url, url: &url::Url) -> bool {
    url.scheme() == "https"
        && url.origin() == origin.origin()
        && url.username().is_empty()
        && url.password().is_none()
}
/// Both swap services use the same Tor-aware transport as ordinary Enhance PIR.
struct SwapTransport<'a, F> {
    http: RoutedTransport<'a, F>,
    enhance: url::Url,
}
impl<'a, F> SwapTransport<'a, F> {
    /// A transport limited to the `enhance` origin.
    fn new(should_exit: &'a F, enhance: url::Url) -> Self {
        Self {
            http: RoutedTransport::new(should_exit),
            enhance,
        }
    }
}
impl<F: Fn() -> bool> Transport for SwapTransport<'_, F> {
    async fn execute(&self, request: Request) -> Result<ResponseBody, ClientError> {
        let url = url::Url::parse(&request.url)
            .map_err(|_| ClientError::Transport("Invalid Enhance URL".into()))?;
        if !allowed_enhance_route(&self.enhance, &url) {
            return Err(ClientError::Transport(
                "Enhance route escaped the selected HTTPS origin".into(),
            ));
        }
        self.http.execute(request).await
    }
}
fn receiver_error(error: RoutedHttpError) -> DirectoryError {
    match error {
        RoutedHttpError::HttpStatus(409 | 410) => DirectoryError::Revision,
        RoutedHttpError::HttpStatus(status) => DirectoryError::Transport(format!("HTTP {status}")),
        RoutedHttpError::Cancelled => DirectoryError::Transport("Cancelled".into()),
        RoutedHttpError::Failed(error) => DirectoryError::Transport(error.to_string()),
    }
}
impl<F: Fn() -> bool> ReceiverTransport for SwapTransport<'_, F> {
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, DirectoryError> {
        self.http
            .bytes(http::Method::GET, url, vec![], limit)
            .await
            .map_err(receiver_error)
    }
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, DirectoryError> {
        self.http
            .bytes(http::Method::POST, url, body, limit)
            .await
            .map_err(receiver_error)
    }
}
/// Holds the wallet write lock for each of a sweep's writes.
struct WalletWriteLock;
impl WriteLock for WalletWriteLock {
    fn write<T>(&self, label: &'static str, write: impl FnOnce() -> T) -> T {
        with_wallet_db_write_lock(label, write)
    }
}
fn error(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Runs pending restore sweeps for at most [`RUN_BUDGET`], returning whether one
/// finished. Sync calls it after reporting completion, so sends never wait for the
/// directory. Failures are logged and retried on a later sync.
pub(super) async fn run(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    should_exit: &impl Fn() -> bool,
) -> bool {
    if network != WalletNetwork::Main || cfg!(ironwood_masquerade) {
        return false;
    }
    let tip = match db.block_fully_scanned() {
        Ok(Some(tip)) => tip,
        Ok(None) => return false,
        Err(e) => {
            log::warn!("Swap recovery deferred: {e}");
            return false;
        }
    };
    let through = ChainPoint {
        height: tip.block_height(),
        hash: tip.block_hash(),
    };
    // Stopping at any await is safe (see `zakura_pir_receiver`).
    let result = tokio::select! {
        biased;
        _ = super::watch_for_exit(should_exit) => return false,
        result = tokio::time::timeout(RUN_BUDGET, run_inner(db, network, through, should_exit)) => {
            result.unwrap_or_else(|_| Err("time budget reached".to_owned()))
        }
    };
    match result {
        Ok(swept) => {
            // Keys identify the wallet's swaps, so only the reasons are logged.
            for (_, e) in &swept.deferred {
                log::warn!("Private swap recovery work deferred: {e}");
            }
            if swept.pending {
                log::warn!("Swap recovery deferred: restore sweeps remain pending");
            }
            swept.finished > 0
        }
        Err(e) => {
            log::warn!("Swap recovery deferred: {e}");
            false
        }
    }
}

/// Runs recovery at `through`, the fully scanned block, if it is also the chain tip.
/// The sync's enhancement checkpoint has already retrieved funding memos, and
/// maintenance has registered their refund keys.
async fn run_inner(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    through: ChainPoint,
    should_exit: &impl Fn() -> bool,
) -> Result<Swept<SwapError>, String> {
    if Some(through.height) != db.chain_height().map_err(error)? {
        return Ok(Swept {
            finished: 0,
            deferred: Vec::new(),
            pending: false,
        });
    }
    let enhance_origin = super::enhancement::payload_endpoint();
    let transport = SwapTransport::new(
        should_exit,
        url::Url::parse(&enhance_origin).map_err(error)?,
    );
    let mut notes = EnhanceNotes::new(&enhance_origin, &transport, &network);
    let accounts = crate::wallet::swap_receiving::software_accounts(db)?;
    zakura_pir_receiver::sweep(
        db,
        &network,
        &accounts,
        through,
        MAINNET_GENESIS,
        &receiver_origin(),
        &transport,
        &mut notes,
        &WalletWriteLock,
        crate::wallet::swap_receiving::receive::now()?,
    )
    .await
    .map_err(error)
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::StreamExt;
    use zakura_pir_enhance::transport::PendingClient;
    use zakura_pir_enhance::{AcceptedAnchor, ClientResourceLimits, GenerationAcceptance};
    use zakura_pir_receiver::receiver_pir::{transport::DirectoryClient, AcceptedCoverage};

    #[test]
    fn enhance_routes_remain_on_the_configured_tls_origin() {
        let parse = |url| url::Url::parse(url).unwrap();
        let origin = parse(super::super::enhancement::DEFAULT_MAINNET_ENDPOINT);
        assert!(allowed_enhance_route(
            &origin,
            &parse("https://enhance-pir.valargroup.dev/v1/enhance/init")
        ));
        for route in [
            "http://enhance-pir.valargroup.dev/v1/enhance/init",
            "https://enhance-pir.valargroup.dev:8443/v1/enhance/init",
            "https://enhance-pir.valargroup.dev.example.com/v1/enhance/init",
            "https://user@enhance-pir.valargroup.dev/v1/enhance/init",
            "http://127.0.0.1:18280/v1/enhance/init",
        ] {
            assert!(!allowed_enhance_route(&origin, &parse(route)), "{route}");
        }
        let local = parse("https://127.0.0.1:18280");
        assert!(allowed_enhance_route(
            &local,
            &parse("https://127.0.0.1:18280/v1/enhance/init")
        ));
        assert!(!allowed_enhance_route(
            &local,
            &parse("https://127.0.0.1/v1/enhance/init")
        ));
    }
    /// Uses only a public zero-OVK chain fixture and independently checked RPC anchors.
    #[tokio::test]
    #[ignore = "requires the isolated PIR services and VIZOR_SWAP_PUBLIC_ANCHORS"]
    async fn public_refund_round_trips_the_vizor_dependency_graph() {
        let _ = rustls::crypto::ring::default_provider().install_default();
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
        let enhance_origin = super::super::enhancement::payload_endpoint();
        let transport = SwapTransport::new(&should_exit, url::Url::parse(&enhance_origin).unwrap());
        let manifest = DirectoryClient::fetch_manifest(&receiver_origin(), &&transport)
            .await
            .unwrap();
        let mut client = DirectoryClient::connect_manifest(
            &receiver_origin(),
            &transport,
            accepted,
            manifest,
            0,
        )
        .await
        .unwrap();
        let proofs = client.witnesses().await.unwrap();
        assert_eq!(
            hex::encode(proofs.root()),
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
        let action = zakura_pir_receiver::receiver_directory::extract::Action {
            cv: field(&fixture, "cv"),
            nullifier: field(&fixture, "nullifier"),
            cmx: field(&fixture, "cmx"),
            ephemeral_key: field(&fixture, "ephemeralKey"),
            enc_ciphertext: field(&fixture, "encCiphertext"),
            out_ciphertext: field(&fixture, "outCiphertext"),
        };
        let receiver = action.recover_receiver().unwrap().unwrap();
        let found = client.lookup(receiver, accepted).await.unwrap();
        let payment = found.iter().find(|p| p.position == 610503).unwrap();
        assert_eq!(payment.height, 3496114);
        proofs.path(610503, action.cmx).unwrap();
        let pending = PendingClient::fetch(&transport, &enhance_origin)
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
