//! Which wallet PIR server the four private products talk to.
//!
//! The config itself (pinned static source, dynamic server list, attestation,
//! explicit selection rules) is the shared `zakura-pir-config` profile; the
//! FRB adapter in `crate::api::pir_config` exposes it to Dart. This module
//! holds only the process's applied choice. That one base serves every
//! product, each client composing its own canonical route below it:
//!
//! ```text
//!   selected base ──▶ Enhance      <base>/enhance/v1
//!                 ├─▶ Status       <base>/status/v1
//!                 ├─▶ Transparent  <base>/transparent/v1
//!                 └─▶ Receiver     <base>/receiver/v1
//! ```
//!
//! There is no failover between servers: with no selection, private PIR work
//! has no server and fails closed exactly as it does when Private queries
//! cannot reach its service. Only config *mirrors* fall through.

mod selection;
#[cfg(test)]
mod tests;

pub(crate) use selection::{
    client_origin, process_selection, selected_server_base, PirProduct, SelectedServer,
};
