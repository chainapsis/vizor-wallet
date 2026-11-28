// The PIR transport's nested async types exceed the default layout query depth.
#![recursion_limit = "256"]

// zcash_voting's proxy delegation switch is unstable and for tests: only a
// debug development build may carry it (see `unstable-proxy-delegation` in
// Cargo.toml).
#[cfg(all(feature = "unstable-proxy-delegation", not(debug_assertions)))]
compile_error!(
    "the unstable-proxy-delegation feature is for debug development builds only; \
     no profile or release build may enable it"
);

pub mod api;
pub mod ffi;
mod frb_generated;
mod log_redaction;
pub mod migration_preparation;
pub mod network_privacy;
mod tor_update_relay;
pub mod wallet;

#[cfg(test)]
mod unstable_proxy_delegation_guard;
