//! Recovery of full transaction payloads after compact-block scanning.
//!
//! The wallet database owns routing: each durable obligation is either
//! private Enhance PIR work or an explicitly public lightwalletd request.
//! This package only executes that decision. In particular, a failed,
//! suspended, or uncovered private request is never converted into a public
//! transaction-ID lookup.

mod coordinator;
mod diagnostics;
pub(super) mod private;
pub(super) mod public;
pub(in crate::wallet::sync_engine) mod queue;

pub(in crate::wallet::sync_engine) use diagnostics::{begin_session, phase};
pub(in crate::wallet::sync_engine) use private::{EnhancePirRunError, RoutedPayloadEnhancement};
pub(in crate::wallet::sync_engine) use queue::queue_stored_transactions;

pub(super) use coordinator::ProductionEnhancementEffects;

#[cfg(test)]
mod tests;
