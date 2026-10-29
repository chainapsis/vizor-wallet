//! The scanning keys the sync engine keeps between scans.
//!
//! Every `scan_cached_blocks` call needs each account's scanning keys, and
//! decoding and deriving them costs more than scanning a block or two. While
//! the app follows the chain tip each sync scans about one block, so the keys
//! are kept here, for the one wallet DB being synced, and reused until an
//! account's stored viewing key changes (the library compares the stored
//! encodings before each scan).
//!
//! The cache holds viewing keys, so it is dropped when the wallet it belongs
//! to goes away: on account deletion, on wallet reset (the DB path changes and
//! the Dart reset path calls [`evict_db`]), and whenever a scan of a different
//! wallet DB begins.

use std::sync::{Mutex, MutexGuard};

use zcash_client_backend::data_api::chain::ScanningKeyCache;
use zcash_client_sqlite::AccountUuid;

/// The scanning keys of at most one wallet DB.
#[derive(Default)]
struct WalletScanningKeys {
    wallet: Option<(String, ScanningKeyCache<AccountUuid>)>,
}

impl WalletScanningKeys {
    /// The cache for the wallet at `db_path`, replacing another wallet's.
    fn for_db(&mut self, db_path: &str) -> &mut ScanningKeyCache<AccountUuid> {
        if self.wallet.as_ref().is_none_or(|(path, _)| path != db_path) {
            self.wallet = Some((db_path.to_owned(), ScanningKeyCache::new()));
        }
        let (_, keys) = self
            .wallet
            .as_mut()
            .expect("the cache was just set for db_path");
        keys
    }

    fn evict(&mut self, db_path: &str) {
        if self
            .wallet
            .as_ref()
            .is_some_and(|(path, _)| path == db_path)
        {
            self.wallet = None;
        }
    }

    #[cfg(test)]
    fn db_path(&self) -> Option<&str> {
        self.wallet.as_ref().map(|(path, _)| path.as_str())
    }
}

static CACHE: Mutex<WalletScanningKeys> = Mutex::new(WalletScanningKeys { wallet: None });

fn cache() -> MutexGuard<'static, WalletScanningKeys> {
    // The cache is refreshed from the DB before every scan, so an entry left
    // by a panicking holder is corrected by the next scan.
    match CACHE.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

/// Runs `scan` with the scanning key cache of the wallet at `db_path`,
/// dropping any other wallet's keys first.
///
/// Scans are serialized by the sync guard and the wallet write lock, so
/// holding the cache for the duration of a scan does not delay another.
pub(super) fn with_cache<T>(
    db_path: &str,
    scan: impl FnOnce(&mut ScanningKeyCache<AccountUuid>) -> T,
) -> T {
    scan(cache().for_db(db_path))
}

/// Drops the cached scanning keys of the wallet at `db_path`, if any.
pub(crate) fn evict_db(db_path: &str) {
    cache().evict(db_path);
}

#[cfg(test)]
mod tests {
    use super::WalletScanningKeys;

    #[test]
    fn a_scan_of_another_wallet_or_an_eviction_drops_the_keys() {
        let mut keys = WalletScanningKeys::default();

        keys.for_db("/wallet-a.db");
        assert_eq!(keys.db_path(), Some("/wallet-a.db"));
        keys.for_db("/wallet-b.db");
        assert_eq!(keys.db_path(), Some("/wallet-b.db"));
        keys.evict("/wallet-a.db");
        assert_eq!(keys.db_path(), Some("/wallet-b.db"));
        keys.evict("/wallet-b.db");
        assert_eq!(keys.db_path(), None);
    }
}
