//! Helpers shared by the swap receiving FFI. Provider polling stays in Dart; allocation
//! is durable in Rust.
use super::*;

/// A swap receiving failure. `message` is display text, never a parsing protocol.
#[derive(Clone, Debug)]
pub struct ReceiveError {
    pub message: String,
}
impl std::fmt::Display for ReceiveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for ReceiveError {}
impl From<String> for ReceiveError {
    fn from(message: String) -> Self {
        Self { message }
    }
}
impl From<&str> for ReceiveError {
    fn from(message: &str) -> Self {
        message.to_owned().into()
    }
}
impl From<zcash_client_sqlite::wallet::swap_receiving::Error> for ReceiveError {
    fn from(error: zcash_client_sqlite::wallet::swap_receiving::Error) -> Self {
        error.to_string().into()
    }
}
pub(crate) fn now() -> Result<i64, String> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs()
        .try_into()
        .map_err(|_| "Clock overflow".into())
}

/// Runs `action` on `uuid`'s account in the wallet at `path`, under the wallet write lock.
pub(crate) fn with_db<T, E: From<String>>(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    action: impl FnOnce(&mut WalletDatabase, AccountUuid) -> Result<T, E>,
) -> Result<T, E> {
    with_wallet_db_write_lock("swap_receiving", || {
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let account = parse_account_uuid(uuid)?;
        action(&mut db, account)
    })
}
