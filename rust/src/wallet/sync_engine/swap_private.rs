//! Restore sweeps of swap keys through the receiver directory. The sweep's rules, chain
//! acceptance and note mutation live in `zakura_pir_receiver` and the wallet library;
//! this module supplies Vizor's routed transport, service origin, write lock and run
//! budget.
use super::enhancement::transport::{RoutedHttpError, RoutedTransport};
use super::WalletDatabase;
use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};
use std::time::Duration;
use zakura_pir_receiver::{DirectoryError, Transport, WriteLock, MAINNET_GENESIS};
use zcash_client_backend::data_api::{transparent_ledger::ChainPoint, WalletRead};

/// The receiver directory's default origin. Use explicit HTTPS origins and never follow
/// service redirects.
const DEFAULT_RECEIVER_ORIGIN: &str = "https://receiver-pir.valargroup.dev";
/// Debug builds only: overrides [`DEFAULT_RECEIVER_ORIGIN`], like Enhance's
/// `VIZOR_ENHANCE_PIR_URL`. Release builds never read it.
#[cfg(debug_assertions)]
const RECEIVER_ORIGIN_ENV: &str = "VIZOR_RECEIVER_PIR_URL";
/// Time one recovery run may take. Sweeps it does not reach wait for a later sync.
const RUN_BUDGET: Duration = Duration::from_secs(180);
/// Time the seen set download before an issuance may take.
const SEEN_BUDGET: Duration = Duration::from_secs(20);
/// Debug builds only: the genesis block hash of the regtest end-to-end tests' chain, as
/// `getblockhash 0` displays it, which their receiver directory commits to. Release
/// builds never read it.
const RECEIVER_GENESIS_ENV: &str = "VIZOR_RECEIVER_PIR_GENESIS";
/// The receiver directory's origin: [`DEFAULT_RECEIVER_ORIGIN`], or in a debug build
/// a configured override.
fn receiver_origin() -> String {
    #[cfg(debug_assertions)]
    if let Ok(origin) = std::env::var(RECEIVER_ORIGIN_ENV) {
        return origin;
    }
    DEFAULT_RECEIVER_ORIGIN.into()
}
/// The genesis block hash, in internal byte order, that receiver directory publications
/// must commit to: mainnet's, or on regtest in a debug build, the configured chain's
/// (see [`RECEIVER_GENESIS_ENV`]).
fn receiver_genesis(network: WalletNetwork) -> Result<[u8; 32], String> {
    if cfg!(debug_assertions) && network == WalletNetwork::Regtest {
        if let Ok(displayed) = std::env::var(RECEIVER_GENESIS_ENV) {
            let mut genesis: [u8; 32] = hex::decode(displayed.trim())
                .ok()
                .and_then(|bytes| bytes.try_into().ok())
                .ok_or("Invalid receiver directory genesis")?;
            genesis.reverse();
            return Ok(genesis);
        }
    }
    Ok(MAINNET_GENESIS)
}
/// The receiver directory uses the same Tor-aware transport as Vizor's other private
/// services.
struct SwapTransport<'a, F> {
    http: RoutedTransport<'a, F>,
}
impl<'a, F> SwapTransport<'a, F> {
    /// A transport that stops when `should_exit` does.
    fn new(should_exit: &'a F) -> Self {
        Self {
            http: RoutedTransport::new(should_exit),
        }
    }
}
/// Maps a receiver directory failure: a session conflict means its publication changed,
/// and anything else, including overload (HTTP 429), is a retryable transport failure.
fn receiver_error(error: RoutedHttpError) -> DirectoryError {
    match error {
        error if error.is_session_conflict() => DirectoryError::Revision,
        RoutedHttpError::HttpStatus(status) => DirectoryError::Transport(format!("HTTP {status}")),
        RoutedHttpError::Cancelled => DirectoryError::Transport("Cancelled".into()),
        RoutedHttpError::Failed(error) => DirectoryError::Transport(error.to_string()),
    }
}
impl<F: Fn() -> bool> Transport for SwapTransport<'_, F> {
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
/// Debug builds only: a plaintext transport for a receiver directory on the loopback
/// interface, which the regtest end-to-end tests serve in process. Every other origin,
/// and every release build, uses [`SwapTransport`].
#[cfg(debug_assertions)]
struct LoopbackTransport {
    client: hyper_util::client::legacy::Client<
        hyper_util::client::legacy::connect::HttpConnector,
        http_body_util::Full<bytes::Bytes>,
    >,
}
#[cfg(debug_assertions)]
impl LoopbackTransport {
    /// A transport for `origin` if it is a plaintext loopback origin.
    fn for_origin(origin: &str) -> Option<Self> {
        let loopback = ["http://127.0.0.1:", "http://localhost:"]
            .iter()
            .any(|prefix| origin.starts_with(prefix));
        loopback.then(|| Self {
            client: hyper_util::client::legacy::Client::builder(
                hyper_util::rt::TokioExecutor::new(),
            )
            .build_http(),
        })
    }
    /// Sends one request, failing like [`SwapTransport`] does.
    async fn send(
        &self,
        method: http::Method,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, DirectoryError> {
        use http_body_util::BodyExt as _;
        let request = http::Request::builder()
            .method(method)
            .uri(url)
            .body(http_body_util::Full::new(bytes::Bytes::from(body)))
            .map_err(|e| DirectoryError::Transport(e.to_string()))?;
        let response = self
            .client
            .request(request)
            .await
            .map_err(|e| DirectoryError::Transport(e.to_string()))?;
        if !response.status().is_success() {
            return Err(receiver_error(RoutedHttpError::HttpStatus(
                response.status().as_u16(),
            )));
        }
        let body = http_body_util::Limited::new(response.into_body(), limit)
            .collect()
            .await
            .map_err(|e| DirectoryError::Transport(e.to_string()))?;
        Ok(body.to_bytes().to_vec())
    }
}
/// The receiver directory's transport: [`SwapTransport`], or in a debug build a
/// [`LoopbackTransport`] for a loopback origin.
enum ReceiverTransport<'a, F> {
    Routed(SwapTransport<'a, F>),
    #[cfg(debug_assertions)]
    Loopback(LoopbackTransport),
}
impl<'a, F> ReceiverTransport<'a, F> {
    /// The transport to `origin`, stopping when `should_exit` does.
    fn new(origin: &str, should_exit: &'a F) -> Self {
        #[cfg(debug_assertions)]
        if let Some(loopback) = LoopbackTransport::for_origin(origin) {
            return Self::Loopback(loopback);
        }
        #[cfg(not(debug_assertions))]
        let _ = origin;
        Self::Routed(SwapTransport::new(should_exit))
    }
}
impl<F: Fn() -> bool> Transport for ReceiverTransport<'_, F> {
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, DirectoryError> {
        match self {
            Self::Routed(transport) => transport.get(url, limit).await,
            #[cfg(debug_assertions)]
            Self::Loopback(transport) => {
                transport.send(http::Method::GET, url, vec![], limit).await
            }
        }
    }
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, DirectoryError> {
        match self {
            Self::Routed(transport) => transport.post(url, body, limit).await,
            #[cfg(debug_assertions)]
            Self::Loopback(transport) => transport.send(http::Method::POST, url, body, limit).await,
        }
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

/// The receiver directory's swap provider seen sets, which incoming and refund issuance
/// check (see `prepare_receive_reservation` and `reserve_refund_key`), over the restore
/// sweep's transport. `None` where one-time IVKs are not `supported`, or when the
/// directory does not answer within [`SEEN_BUDGET`]. Incoming issuance then counts every
/// quote as seen, and refund issuance skips only the indexes funding memos recover.
pub(crate) async fn fetch_seen(network: WalletNetwork) -> Option<zakura_pir_receiver::Seen> {
    if !crate::wallet::one_time_ivk::supported(network) {
        return None;
    }
    let genesis = match receiver_genesis(network) {
        Ok(genesis) => genesis,
        Err(e) => {
            log::warn!("Swap seen set unavailable: {e}");
            return None;
        }
    };
    let should_exit = || false;
    let origin = receiver_origin();
    let transport = ReceiverTransport::new(&origin, &should_exit);
    let fetch = zakura_pir_receiver::fetch_seen(&origin, &transport, genesis);
    match tokio::time::timeout(SEEN_BUDGET, fetch).await {
        Ok(Ok(seen)) => Some(seen),
        Ok(Err(e)) => {
            log::warn!("Swap seen set unavailable: {e}");
            None
        }
        Err(_) => {
            log::warn!("Swap seen set unavailable: timed out");
            None
        }
    }
}

/// Runs pending restore sweeps for at most [`RUN_BUDGET`], returning whether one
/// finished. Sync runs it as its last follow-up after reporting completion, so sends
/// never wait for the directory, and only where one-time IVKs are `supported`.
/// Failures are logged and retried on a later sync.
pub(super) async fn run(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    should_exit: &impl Fn() -> bool,
) -> bool {
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
        Ok(finished) => finished,
        Err(e) => {
            log::warn!("Swap recovery deferred: {e}");
            false
        }
    }
}

/// Runs recovery at `through`, the fully scanned block, if it is also the chain tip, and
/// returns whether a sweep finished. Refund keys from funding memos that this sync's
/// enhancement retrieved are swept next sync (see `run_sync_impl`). Each
/// software account gets one `sweep`, which sweeps at most one batch of its due keys;
/// the rest wait for a later sync. An account whose run fails does not stop the others.
async fn run_inner(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    through: ChainPoint,
    should_exit: &impl Fn() -> bool,
) -> Result<bool, String> {
    if Some(through.height) != db.chain_height().map_err(error)? {
        return Ok(false);
    }
    let origin = receiver_origin();
    let transport = ReceiverTransport::new(&origin, should_exit);
    let genesis = receiver_genesis(network)?;
    let now = crate::wallet::one_time_ivk::now()?;
    let mut finished = false;
    for account in crate::wallet::one_time_ivk::software_accounts(db)? {
        let swept = zakura_pir_receiver::sweep(
            db,
            &network,
            account,
            through,
            genesis,
            &origin,
            &transport,
            &WalletWriteLock,
            now,
        )
        .await;
        match swept {
            Ok(swept) => {
                // Keys identify the wallet's swaps, so only the reasons are logged.
                for (_, e) in &swept.deferred {
                    log::warn!("Private swap recovery work deferred: {e}");
                }
                if swept.pending {
                    log::warn!("Swap recovery deferred: restore sweeps remain pending");
                }
                finished |= swept.finished > 0;
            }
            Err(e) => log::warn!("Swap recovery deferred: {e}"),
        }
    }
    Ok(finished)
}

#[cfg(test)]
mod tests {
    use super::*;
    use zakura_pir_receiver::receiver_pir::{transport::DirectoryClient, AcceptedCoverage};

    #[test]
    fn receiver_overload_is_retryable_and_conflicts_mean_a_new_publication() {
        assert!(matches!(
            receiver_error(RoutedHttpError::HttpStatus(429)),
            DirectoryError::Transport(_)
        ));
        for status in [409, 410] {
            assert!(matches!(
                receiver_error(RoutedHttpError::HttpStatus(status)),
                DirectoryError::Revision
            ));
        }
    }
    /// Reads the live directory's seen sets, as issuance does.
    #[tokio::test]
    #[ignore = "requires the live receiver directory"]
    async fn issuance_reads_the_live_seen_sets() {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let seen = fetch_seen(WalletNetwork::Main).await.unwrap();
        assert!(seen.since() < seen.until());
        assert_eq!(seen.contains(&[[0; 43]]).len(), 1);
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
        let transport = SwapTransport::new(&should_exit);
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
        println!(
            "Vizor dependencies verified receiver PIR and the common witness at position 610503"
        );
    }
}
