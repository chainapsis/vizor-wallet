//! The process-wide selected server and the product routes derived from it.

use std::sync::{
    atomic::{AtomicU64, Ordering},
    RwLock,
};

use zakura_pir_config::ServerBase;
pub(crate) use zakura_pir_protocol::endpoint::PirProduct;

/// The origin handed to `product`'s client: the selected server base. The
/// clients compose `<base>/<product>/v1/...` from it themselves
/// ([`PirProduct::route_prefix`]), so the base is passed bare.
///
/// Debug builds may name a test server through the product's environment
/// variable, but only while the user has selected nothing, so a test
/// override never redirects a user's choice.
pub(crate) fn client_origin(product: PirProduct) -> Option<String> {
    if let Some(base) = selected_server_base() {
        return Some(base);
    }
    #[cfg(debug_assertions)]
    if let Ok(origin) = std::env::var(debug_override_env(product)) {
        return Some(origin);
    }
    let _ = product;
    None
}

#[cfg(debug_assertions)]
fn debug_override_env(product: PirProduct) -> &'static str {
    match product {
        PirProduct::Enhance => "VIZOR_ENHANCE_PIR_URL",
        PirProduct::Status => "VIZOR_STATUS_PIR_URL",
        PirProduct::Transparent => "VIZOR_TRANSPARENT_PIR_URL",
        PirProduct::Receiver => "VIZOR_RECEIVER_PIR_URL",
    }
}

/// A selected server base and the generation that counts its changes.
///
/// The generation lets work that captured it before an await tell that its
/// server is no longer the selected one.
///
/// A switch is staged: [`begin_switch`](Self::begin_switch) drops the old
/// base and marks cleanup pending, and only
/// [`finish_switch`](Self::finish_switch), after the caller's cleanup
/// succeeded, installs the new one. A failed cleanup therefore leaves no
/// server, and the pending mark makes the next apply of any base, the same
/// one included, run cleanup again.
pub(crate) struct SelectedServer {
    state: RwLock<SelectionState>,
    generation: AtomicU64,
}

struct SelectionState {
    base: Option<String>,
    cleanup_pending: bool,
}

/// A switch whose cleanup is under way; [`SelectedServer::finish_switch`]
/// installs its target.
#[must_use]
pub(crate) struct PendingSwitch {
    target: Option<String>,
}

impl SelectedServer {
    pub(crate) const fn new() -> Self {
        Self {
            state: RwLock::new(SelectionState {
                base: None,
                cleanup_pending: false,
            }),
            generation: AtomicU64::new(0),
        }
    }

    pub(crate) fn base(&self) -> Option<String> {
        self.read().base.clone()
    }

    pub(crate) fn generation(&self) -> u64 {
        self.generation.load(Ordering::SeqCst)
    }

    /// Starts switching to `base`, or to no server with `None`.
    ///
    /// Returns `None` when `base` is already selected and no earlier cleanup
    /// is outstanding, so a repeated apply at startup or resume does not tear
    /// down sessions. Otherwise the old base is dropped at once, so nothing
    /// uses it while its state is cleaned up. An invalid base changes nothing.
    pub(crate) fn begin_switch(&self, base: Option<&str>) -> Result<Option<PendingSwitch>, String> {
        let target = base
            .map(|base| {
                ServerBase::parse(base)
                    .map(|base| base.as_str().to_owned())
                    .map_err(|error| error.to_string())
            })
            .transpose()?;
        let mut state = self.write();
        if state.base == target && !state.cleanup_pending {
            return Ok(None);
        }
        state.cleanup_pending = true;
        if state.base.take().is_some() {
            self.generation.fetch_add(1, Ordering::SeqCst);
        }
        Ok(Some(PendingSwitch { target }))
    }

    /// Installs the target of a switch whose cleanup succeeded and returns
    /// the generation.
    pub(crate) fn finish_switch(&self, switch: PendingSwitch) -> u64 {
        let mut state = self.write();
        state.cleanup_pending = false;
        state.base = switch.target;
        if state.base.is_some() {
            return self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        }
        self.generation()
    }

    /// Whether a switch's cleanup failed and has not yet been re-run.
    #[cfg(test)]
    pub(crate) fn cleanup_pending(&self) -> bool {
        self.read().cleanup_pending
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, SelectionState> {
        self.state
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, SelectionState> {
        self.state
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

/// The process's selection, applied by Dart from the user's saved choice.
static SELECTION: SelectedServer = SelectedServer::new();

pub(crate) fn selected_server_base() -> Option<String> {
    SELECTION.base()
}

pub(crate) fn process_selection() -> &'static SelectedServer {
    &SELECTION
}
