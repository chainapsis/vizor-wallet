//! Private status observation. A selected private lookup never issues a txid RPC.
use super::super::{
    super::WalletDatabase, transport::StatusPirTransport, DEFAULT_MAINNET_ENDPOINT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::transaction_data::{LookupError, TransactionObservation};
use std::time::{SystemTime, UNIX_EPOCH};
use zakura_pir_status::{
    transport::{PendingClient, StatusPirClient},
    AcceptedAnchor, Error, LocalCoverageContext, Observation,
};
use zakura_transaction_status::{
    StatusError, StatusObservation, StatusRequest, StatusSession, StatusSource,
};
use zcash_client_backend::data_api::WalletRead;
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;

const MAINNET_GENESIS_DISPLAY: &str =
    "00040fe8ec8471911baa1db1266ea15dd06b4a8a5c453883c000b031973dce08";
const ENDPOINT_ENV: &str = "VIZOR_STATUS_PIR_URL";

fn status_endpoint() -> String {
    std::env::var(ENDPOINT_ENV).unwrap_or_else(|_| DEFAULT_MAINNET_ENDPOINT.into())
}

fn now_ms() -> Result<u64, LookupError> {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| LookupError::Malformed)?;
    u64::try_from(elapsed.as_millis()).map_err(|_| LookupError::Malformed)
}

/// The session clock. An unreadable clock reads as far future, which fails
/// every manifest freshness check rather than accepting stale routing.
fn session_now_ms() -> u64 {
    now_ms().unwrap_or(u64::MAX)
}

type SessionClient = StatusPirClient<fn() -> u64>;

fn mainnet_genesis() -> [u8; 32] {
    let mut bytes: [u8; 32] = hex::decode(MAINNET_GENESIS_DISPLAY)
        .expect("fixed mainnet genesis hash")
        .try_into()
        .expect("32-byte mainnet genesis hash");
    bytes.reverse();
    bytes
}

fn classify(error: Error) -> LookupError {
    match error {
        Error::Unsupported => LookupError::Unsupported,
        Error::CoverageIncomplete => LookupError::CoverageIncomplete,
        Error::Stale => LookupError::Stale,
        Error::Capacity => LookupError::Unavailable,
        Error::Timeout => LookupError::Timeout,
        Error::Cancelled => LookupError::Cancelled,
        Error::Malformed => LookupError::Malformed,
        Error::Unavailable | Error::Pir => LookupError::Unavailable,
    }
}

/// App-owned private source for the wallet-libraries status reader. Opening is
/// lazy, so no PIR request occurs when public status is selected.
pub(crate) struct PrivateStatusSource<'a, F> {
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
    route_policy: StatusRoutePolicy,
}

#[derive(Clone, Copy)]
enum StatusRoutePolicy {
    WalletPreference,
    ForceDirect,
}

impl<'a, F: Fn() -> bool + Sync> PrivateStatusSource<'a, F> {
    pub(crate) fn new(
        db_path: &'a str,
        network: WalletNetwork,
        should_exit: &'a F,
        direct_only: bool,
    ) -> Self {
        Self {
            db_path,
            network,
            should_exit,
            route_policy: if direct_only {
                StatusRoutePolicy::ForceDirect
            } else {
                StatusRoutePolicy::WalletPreference
            },
        }
    }
}

fn status_error(error: LookupError) -> StatusError {
    match error {
        LookupError::Unsupported => StatusError::Unsupported,
        LookupError::Unavailable => StatusError::Unavailable,
        LookupError::CoverageIncomplete => StatusError::CoverageIncomplete,
        LookupError::Stale => StatusError::Stale,
        LookupError::Timeout => StatusError::Timeout,
        LookupError::Malformed => StatusError::Malformed,
        LookupError::Cancelled => StatusError::Cancelled,
        LookupError::Transport { code } => StatusError::Transport { code },
        LookupError::LocalStorage => StatusError::LocalStorage,
    }
}

/// A wallet DB read failure is local, not a Status PIR outage: the caller must
/// fail the sync instead of deferring private status for the session. The
/// variant carries no detail, so it is logged here.
fn local_storage(context: &str, error: impl std::fmt::Display) -> LookupError {
    log::error!("status_pir local wallet read failed context={context}: {error}");
    LookupError::LocalStorage
}

fn open_anchor_db(db_path: &str, network: WalletNetwork) -> Result<WalletDatabase, LookupError> {
    crate::wallet::db::open_wallet_db_readonly_with_timeout(
        db_path,
        network,
        crate::wallet::db::READ_DB_BUSY_TIMEOUT,
    )
    .map_err(|error| local_storage("open", error))
}

impl<'a, F: Fn() -> bool + Sync> StatusSource for PrivateStatusSource<'a, F> {
    type Session = PrivateStatusSession<'a, F>;

    async fn open(self) -> Result<Self::Session, StatusError> {
        begin_from_db_path(
            self.db_path,
            self.network,
            self.should_exit,
            self.route_policy,
        )
        .await
        .map_err(status_error)
    }
}

impl<F: Fn() -> bool + Sync> StatusSession for PrivateStatusSession<'_, F> {
    async fn observe(&mut self, request: StatusRequest) -> Result<StatusObservation, StatusError> {
        let observation = PrivateStatusSession::observe(self, request.txid, request.coverage)
            .await
            .map_err(status_error)?;
        Ok(match observation {
            TransactionObservation::NotFound => StatusObservation::NotFound,
            TransactionObservation::Mempool => StatusObservation::Mempool,
            TransactionObservation::Mined(height) => StatusObservation::Mined(height),
            TransactionObservation::Forked => StatusObservation::Forked,
        })
    }
}

/// A snapshot anchored below the caller's decision height still proves presence:
/// mined, mempool, and forked records are positive observations. Drop the bound so
/// the library queries instead of rejecting up front, and mark the lookup
/// positive-only so absence is never reported for heights the snapshot does not cover.
fn bound_coverage(
    coverage: LocalCoverageContext,
    anchor_height: u32,
) -> (LocalCoverageContext, bool) {
    match coverage.required_through {
        Some(required) if required > anchor_height => (
            LocalCoverageContext {
                required_through: None,
                ..coverage
            },
            true,
        ),
        _ => (coverage, false),
    }
}

/// Absence proven only up to the anchor is inconclusive for a later decision height.
fn require_bound_for_absence(
    observation: Observation,
    positive_only: bool,
) -> Result<Observation, LookupError> {
    match observation {
        Observation::NotFound if positive_only => Err(LookupError::CoverageIncomplete),
        observation => Ok(observation),
    }
}

fn accepted_anchor(
    db: &WalletDatabase,
    manifest: &zakura_pir_status::Manifest,
) -> Result<AcceptedAnchor, LookupError> {
    if manifest.network != mainnet_genesis() {
        return Err(LookupError::Malformed);
    }
    let anchor_height = BlockHeight::from_u32(manifest.anchor_height);
    let scanned = db
        .block_fully_scanned()
        .map_err(|error| local_storage("block_fully_scanned", error))?;
    if !scanned.is_some_and(|meta| meta.block_height() >= anchor_height) {
        return Err(LookupError::Unavailable);
    }
    let local_hash = db
        .get_block_hash(anchor_height)
        .map_err(|error| local_storage("get_block_hash", error))?
        // Scanned but hashless is not a read failure: wait for scanning.
        .ok_or(LookupError::Unavailable)?;
    if local_hash.0 != manifest.anchor_hash {
        return Err(LookupError::Malformed);
    }
    Ok(AcceptedAnchor {
        network: mainnet_genesis(),
        height: manifest.anchor_height,
        hash: local_hash.0,
    })
}

/// One accepted generation and reusable PIR setup for a batch of status work.
pub(crate) struct PrivateStatusSession<'a, F> {
    route: StatusPirTransport<'a, F>,
    client: tokio::sync::Mutex<SessionClient>,
    endpoint: String,
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
}

impl<F: Fn() -> bool + Sync> PrivateStatusSession<'_, F> {
    async fn refresh(&self) -> Result<SessionClient, LookupError> {
        if (self.should_exit)() {
            return Err(LookupError::Cancelled);
        }
        initialize(&self.route, &self.endpoint, self.db_path, self.network).await
    }

    fn check_anchor(&self, client: &SessionClient) -> Result<(), LookupError> {
        let db = open_anchor_db(self.db_path, self.network)?;
        accepted_anchor(&db, client.manifest())?;
        Ok(())
    }

    async fn observe(
        &self,
        txid: TxId,
        coverage: LocalCoverageContext,
    ) -> Result<TransactionObservation, LookupError> {
        let mut client = self.client.lock().await;
        let mut retried = false;
        let mut positive_only;
        let observation = loop {
            self.check_anchor(&client)?;
            let bounded;
            (bounded, positive_only) = bound_coverage(coverage, client.manifest().anchor_height);
            let result = client.observe(&self.route, txid.as_ref(), bounded).await;
            let conflict = matches!(&result, Err(Error::Unavailable))
                && self.route.take_status_session_conflict();
            match result {
                Err(Error::Unavailable) if conflict && !retried => {
                    *client = self.refresh().await?;
                    retried = true;
                }
                result => break result.map_err(classify)?,
            }
        };
        let observation = require_bound_for_absence(observation, positive_only)?;
        self.check_anchor(&client)?;
        if (self.should_exit)() {
            return Err(LookupError::Cancelled);
        }
        Ok(match observation {
            Observation::NotFound => TransactionObservation::NotFound,
            Observation::Mempool => TransactionObservation::Mempool,
            Observation::Mined(height) => {
                TransactionObservation::Mined(BlockHeight::from_u32(height))
            }
            Observation::Forked => TransactionObservation::Forked,
        })
    }
}

async fn initialize<F: Fn() -> bool + Sync>(
    route: &StatusPirTransport<'_, F>,
    endpoint: &str,
    db_path: &str,
    network: WalletNetwork,
) -> Result<SessionClient, LookupError> {
    for attempt in 0..2 {
        let pending = PendingClient::fetch(route, endpoint, session_now_ms as fn() -> u64)
            .await
            .map_err(classify)?;
        let anchor = {
            let db = open_anchor_db(db_path, network)?;
            accepted_anchor(&db, pending.manifest())?
        };
        let result = pending.accept(route, &anchor).await;
        let conflict =
            matches!(&result, Err(Error::Unavailable)) && route.take_status_session_conflict();
        if conflict && attempt == 0 {
            continue;
        }
        return result.map_err(classify);
    }
    unreachable!("bounded status initialization returns on second attempt")
}

/// Use a read-only DB connection for status callers outside the sync engine.
/// No database write lock is held during the network request.
async fn begin_from_db_path<'a, F: Fn() -> bool + Sync>(
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
    route_policy: StatusRoutePolicy,
) -> Result<PrivateStatusSession<'a, F>, LookupError> {
    if should_exit() {
        return Err(LookupError::Cancelled);
    }
    let endpoint = status_endpoint();
    let route = match route_policy {
        StatusRoutePolicy::WalletPreference => StatusPirTransport::new(should_exit),
        StatusRoutePolicy::ForceDirect => StatusPirTransport::new_direct(should_exit),
    };
    let client = initialize(&route, &endpoint, db_path, network).await?;
    Ok(PrivateStatusSession {
        route,
        client: tokio::sync::Mutex::new(client),
        endpoint,
        db_path,
        network,
        should_exit,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mainnet_identity_uses_protocol_byte_order() {
        let mut display = mainnet_genesis();
        display.reverse();
        assert_eq!(hex::encode(display), MAINNET_GENESIS_DISPLAY);
    }

    #[test]
    fn coverage_errors_never_become_not_found() {
        assert_eq!(
            classify(Error::CoverageIncomplete),
            LookupError::CoverageIncomplete
        );
        assert_eq!(classify(Error::Stale), LookupError::Stale);
        assert_eq!(classify(Error::Unavailable), LookupError::Unavailable);
    }

    #[test]
    fn unreadable_wallet_db_is_local_storage_not_an_outage() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("missing").join("wallet.db");
        let result = open_anchor_db(missing.to_str().unwrap(), WalletNetwork::Main);
        assert!(
            matches!(result, Err(LookupError::LocalStorage)),
            "a local open failure must not read as Unavailable"
        );
        assert_eq!(
            status_error(LookupError::LocalStorage),
            StatusError::LocalStorage
        );
    }

    fn coverage(required_through: Option<u32>) -> LocalCoverageContext {
        LocalCoverageContext {
            earliest_possible_inclusion: Some(90),
            required_through,
        }
    }

    #[test]
    fn decision_height_above_anchor_queries_positive_only() {
        let (bounded, positive_only) = bound_coverage(coverage(Some(110)), 100);
        assert_eq!(bounded.required_through, None);
        assert_eq!(bounded.earliest_possible_inclusion, Some(90));
        assert!(positive_only);

        for required in [Some(100), Some(99), None] {
            let (bounded, positive_only) = bound_coverage(coverage(required), 100);
            assert_eq!(bounded.required_through, required);
            assert!(!positive_only);
        }
    }

    #[test]
    fn positive_only_lookup_never_reports_absence() {
        assert_eq!(
            require_bound_for_absence(Observation::NotFound, true),
            Err(LookupError::CoverageIncomplete)
        );
        assert_eq!(
            require_bound_for_absence(Observation::NotFound, false),
            Ok(Observation::NotFound)
        );
        for positive in [
            Observation::Mined(100),
            Observation::Mempool,
            Observation::Forked,
        ] {
            assert_eq!(require_bound_for_absence(positive, true), Ok(positive));
        }
    }
}
