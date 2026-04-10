//! Tor transport for lightwalletd gRPC.
//!
//! Thin wrapper around `zcash_client_backend::tor::Client`, which itself
//! wraps `arti_client::TorClient<PreferredRuntime>` and provides the
//! gRPC-over-Tor bridge (the `connect_to_lightwalletd(Uri)` method).
//! Zashi's `backend-lib/src/main/rust/tor.rs` follows the same pattern.
//!
//! Key design decisions:
//!
//! - **Process-wide client via `tokio::sync::OnceCell`.** Bootstrapping
//!   Tor is expensive (10-40s on first run, fetching the consensus and
//!   microdescriptors). Subsequent calls reuse the cached client, so
//!   a single lazy-initialised global gives every lightwalletd
//!   connection the same bootstrap amortisation.
//!
//! - **Isolated client per connection.** Every call to
//!   [`connect_lightwalletd`] does `client.isolated_client()` so each
//!   lightwalletd stream uses a separate Tor circuit. An observer
//!   linking multiple gRPC calls to the same wallet is the exact threat
//!   we're trying to avoid; sharing circuits defeats the purpose.
//!
//! - **`LwdTorConnection` owns the isolated client.** The isolated
//!   client must live at least as long as the `CompactTxStreamerClient`
//!   it backs — dropping it while the connection is in use would tear
//!   down the circuit mid-stream. The returned struct keeps the
//!   isolated client in a private field purely as a drop-order guard.
//!
//! - **`fs_mistrust::MistrustBuilder::dangerously_trust_everyone`**
//!   disables arti's filesystem-permissions checks. On iOS and Android
//!   the app sandbox is the real isolation boundary, not POSIX mode
//!   bits, and arti's default checks reject the mobile data directory
//!   with an "untrusted directory" error. Zashi does the same thing.
//!
//! Nothing in this module is wired up yet — commit 2.4 adds the
//! `USE_TOR` branch in `open_lwd_channel` that actually calls
//! [`connect_lightwalletd`], and a Dart-side toggle in commit 2.5.

#![allow(dead_code)] // consumed by commit 2.4 and later

use std::path::PathBuf;

use tokio::sync::OnceCell;
use tonic::transport::{Channel, Uri};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_client_backend::tor::{Client as TorClient, DormantMode};

use crate::wallet::sync_engine::SyncError;

/// Process-wide Tor client. Lazily bootstrapped on first call to
/// [`get_or_init_client`]. Subsequent calls reuse the cached handle —
/// the bootstrap cost is paid once per app launch.
///
/// `tokio::sync::OnceCell::const_new` lets us put this in static
/// storage without an `Arc` / `lazy_static` macro. The stored
/// `TorClient` is itself cheap to clone (it's a handle to an internal
/// `Arc`-reference-counted state).
static TOR_CLIENT: OnceCell<TorClient> = OnceCell::const_new();

/// Type returned by [`connect_lightwalletd`] alongside the
/// `CompactTxStreamerClient`. Callers must hold this alive for as long
/// as they use the accompanying client — dropping it tears down the
/// underlying Tor circuit.
///
/// Exposed as a plain `TorClient` rather than wrapped in a struct so
/// the caller can destructure the return of `connect_lightwalletd`
/// into independent `let` bindings; the guard naturally lives for the
/// scope of the enclosing function without further ceremony.
pub(crate) type IsolatedCircuitGuard = TorClient;

/// Returns a handle to the process-wide Tor client, bootstrapping it
/// on first call. `tor_dir` must be a writable directory the app owns
/// — typically `<app_support>/tor`. The directory is created if it
/// does not exist.
///
/// After the first successful call the `tor_dir` parameter is ignored:
/// the cached client uses whatever path was passed on bootstrap. This
/// matches the usual "app_support dir never changes for a given app
/// install" assumption.
pub(crate) async fn get_or_init_client(tor_dir: PathBuf) -> Result<TorClient, SyncError> {
    TOR_CLIENT
        .get_or_try_init(move || async move {
            log::info!("tor: bootstrapping client at {}", tor_dir.display());
            tokio::fs::create_dir_all(&tor_dir)
                .await
                .map_err(|e| SyncError::net(format!("tor_dir create: {e}")))?;
            // `dangerously_trust_everyone` disables arti's filesystem
            // permission checks. See the module-level comment for why
            // this is correct on mobile.
            let client = TorClient::create(&tor_dir, |p| {
                p.dangerously_trust_everyone();
            })
            .await
            .map_err(|e| SyncError::net(format!("tor bootstrap: {e}")))?;
            log::info!("tor: client bootstrapped");
            Ok::<_, SyncError>(client)
        })
        .await
        .map(|c| c.clone())
}

/// Opens a new lightwalletd gRPC connection over a freshly-isolated
/// Tor circuit. Returns `(client, circuit_guard)`: the caller must
/// keep `circuit_guard` in scope for as long as they use `client` so
/// the underlying Tor circuit is not dropped mid-stream.
pub(crate) async fn connect_lightwalletd(
    tor_dir: PathBuf,
    lightwalletd_url: &str,
) -> Result<(CompactTxStreamerClient<Channel>, IsolatedCircuitGuard), SyncError> {
    let client = get_or_init_client(tor_dir).await?;
    let uri: Uri = lightwalletd_url
        .parse()
        .map_err(|e| SyncError::net(format!("tor: invalid URL {lightwalletd_url}: {e}")))?;
    let isolated = client.isolated_client();
    let conn = isolated
        .connect_to_lightwalletd(uri)
        .await
        .map_err(|e| SyncError::net(format!("tor lwd connect: {e}")))?;
    Ok((conn, isolated))
}

/// Flips the process-wide Tor client into or out of `DormantMode::Soft`.
/// Call with `true` when the app goes to background to stop arti's
/// circuit-maintenance background tasks, and `false` on foreground to
/// resume them. If Tor hasn't been bootstrapped yet, this is a no-op.
pub(crate) async fn set_dormant(tor_dir: PathBuf, dormant: bool) -> Result<(), SyncError> {
    // Only act if we've already bootstrapped. A cold dormant call
    // shouldn't force a bootstrap it didn't ask for.
    if !TOR_CLIENT.initialized() {
        return Ok(());
    }
    let client = get_or_init_client(tor_dir).await?;
    let mode = if dormant {
        DormantMode::Soft
    } else {
        DormantMode::Normal
    };
    client.set_dormant(mode);
    log::info!("tor: set_dormant({dormant})");
    Ok(())
}
