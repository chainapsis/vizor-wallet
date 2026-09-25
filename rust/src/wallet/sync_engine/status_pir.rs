//! Private status observation. A selected private lookup never issues a txid RPC.
use super::{enhance_pir::RoutedTransport, WalletDatabase};
use crate::wallet::network::WalletNetwork;
use crate::wallet::transaction_data::{LookupError, TransactionObservation};
use std::time::{SystemTime, UNIX_EPOCH};
use zakura_pir_status::{
    transport::{PendingClient, StatusPirClient},
    AcceptedAnchor, Error, LocalCoverageContext, Observation,
};
use zakura_transaction_status::{
    StatusError, StatusMode, StatusObservation, StatusReader, StatusRequest, StatusSession,
    StatusSource,
};
use zcash_client_backend::data_api::WalletRead;
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;

const MAINNET_GENESIS_DISPLAY: &str =
    "00040fe8ec8471911baa1db1266ea15dd06b4a8a5c453883c000b031973dce08";
const ENDPOINT_ENV: &str = "VIZOR_STATUS_PIR_URL";
const DEFAULT_MAINNET_ENDPOINT: &str = "https://enhance-pir.valargroup.dev";

fn status_endpoint() -> String {
    std::env::var(ENDPOINT_ENV).unwrap_or_else(|_| DEFAULT_MAINNET_ENDPOINT.into())
}

fn now_ms() -> Result<u64, LookupError> {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| LookupError::Malformed)?;
    u64::try_from(elapsed.as_millis()).map_err(|_| LookupError::Malformed)
}

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

/// The existing private-enhancement preference selects status privacy only
/// after the independently qualified release gate is enabled.
pub(crate) fn enabled(network: WalletNetwork) -> bool {
    enabled_for_preference(network, crate::api::sync::enhance_pir_enabled())
}

pub(crate) fn enabled_for_preference(network: WalletNetwork, preference: bool) -> bool {
    network == WalletNetwork::Main
        && preference
        && (option_env!("VIZOR_STATUS_PIR_RELEASE_READY") == Some("1")
            || std::env::var("VIZOR_STATUS_PIR_RELEASE_READY").is_ok_and(|value| value == "1"))
}

/// Assemble the app's policy once for foreground and read-only callers.
/// The public source is lazy; selecting private status never opens it.
pub(crate) fn reader<'a, F, P>(
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
    public_source: P,
) -> StatusReader<P, Source<'a, F>>
where
    F: Fn() -> bool + Sync,
    P: StatusSource,
{
    let mode = if enabled(network) {
        StatusMode::PrivatePir
    } else {
        StatusMode::PublicLightwalletd
    };
    StatusReader::new(
        mode,
        public_source,
        Source::new(db_path, network, should_exit, false),
    )
}

/// App-owned private source for the wallet-libraries status reader. Opening is
/// lazy, so no PIR request occurs when public status is selected.
pub(crate) struct Source<'a, F> {
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
    direct_only: bool,
}

impl<'a, F: Fn() -> bool + Sync> Source<'a, F> {
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
            direct_only,
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
    }
}

impl<'a, F: Fn() -> bool + Sync> StatusSource for Source<'a, F> {
    type Session = Session<'a, F>;

    async fn open(self) -> Result<Self::Session, StatusError> {
        begin_from_db_path(
            self.db_path,
            self.network,
            self.should_exit,
            self.direct_only,
        )
        .await
        .map_err(status_error)
    }
}

impl<F: Fn() -> bool + Sync> StatusSession for Session<'_, F> {
    async fn observe(&mut self, request: StatusRequest) -> Result<StatusObservation, StatusError> {
        let observation = Session::observe(self, request.txid, request.coverage)
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
        .map_err(|_| LookupError::Unavailable)?;
    if !scanned.is_some_and(|meta| meta.block_height() >= anchor_height) {
        return Err(LookupError::Unavailable);
    }
    let local_hash = db
        .get_block_hash(anchor_height)
        .map_err(|_| LookupError::Unavailable)?
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
pub(crate) struct Session<'a, F> {
    route: RoutedTransport<'a, F>,
    client: tokio::sync::Mutex<StatusPirClient>,
    endpoint: String,
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
}

impl<F: Fn() -> bool + Sync> Session<'_, F> {
    async fn refresh(&self) -> Result<StatusPirClient, LookupError> {
        if (self.should_exit)() {
            return Err(LookupError::Cancelled);
        }
        initialize(&self.route, &self.endpoint, self.db_path, self.network).await
    }

    fn check_anchor(&self, client: &StatusPirClient) -> Result<(), LookupError> {
        let db = crate::wallet::db::open_wallet_db_readonly_with_timeout(
            self.db_path,
            self.network,
            crate::wallet::db::READ_DB_BUSY_TIMEOUT,
        )
        .map_err(|_| LookupError::Unavailable)?;
        accepted_anchor(&db, client.manifest())?;
        Ok(())
    }

    pub(crate) async fn observe(
        &self,
        txid: TxId,
        coverage: LocalCoverageContext,
    ) -> Result<TransactionObservation, LookupError> {
        let mut client = self.client.lock().await;
        let mut retried = false;
        let observation = loop {
            self.check_anchor(&client)?;
            let result = client
                .observe(&self.route, txid.as_ref(), coverage, || {
                    now_ms().unwrap_or(u64::MAX)
                })
                .await;
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
    route: &RoutedTransport<'_, F>,
    endpoint: &str,
    db_path: &str,
    network: WalletNetwork,
) -> Result<StatusPirClient, LookupError> {
    for attempt in 0..2 {
        let pending = PendingClient::fetch(route, endpoint, || now_ms().unwrap_or(u64::MAX))
            .await
            .map_err(classify)?;
        let anchor = {
            let db = crate::wallet::db::open_wallet_db_readonly_with_timeout(
                db_path,
                network,
                crate::wallet::db::READ_DB_BUSY_TIMEOUT,
            )
            .map_err(|_| LookupError::Unavailable)?;
            accepted_anchor(&db, pending.manifest())?
        };
        let result = pending.accept(route, &anchor, now_ms()?).await;
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
pub(crate) async fn begin_from_db_path<'a, F: Fn() -> bool + Sync>(
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
    direct_only: bool,
) -> Result<Session<'a, F>, LookupError> {
    if should_exit() {
        return Err(LookupError::Cancelled);
    }
    let endpoint = status_endpoint();
    let route = if direct_only {
        RoutedTransport::new_direct(should_exit)
    } else {
        RoutedTransport::new(should_exit)
    };
    let client = initialize(&route, &endpoint, db_path, network).await?;
    Ok(Session {
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
    fn private_selection_requires_preference_and_mainnet() {
        assert!(!enabled_for_preference(WalletNetwork::Main, false));
        assert!(!enabled_for_preference(WalletNetwork::Test, true));
        assert!(!enabled_for_preference(WalletNetwork::Regtest, true));
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
}
