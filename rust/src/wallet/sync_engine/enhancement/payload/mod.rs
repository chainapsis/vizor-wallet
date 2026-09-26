//! Recovery of full transaction payloads after compact-block scanning.
//!
//! The wallet database owns routing: each durable obligation is either
//! private Enhance PIR work or an explicitly public lightwalletd request.
//! This package only executes that decision. In particular, a failed,
//! suspended, or uncovered private request is never converted into a public
//! transaction-ID lookup.

#[path = "../scheduler.rs"]
mod coordinator;
mod diagnostics;
#[path = "../private_pir.rs"]
pub(super) mod private_pir;
#[path = "../public_payload.rs"]
pub(super) mod public_lwd;
pub(super) mod queue;

pub(in crate::wallet::sync_engine) use diagnostics::{begin_session, phase};
pub(in crate::wallet::sync_engine) use private_pir::{
    EnhancePirRunError, RoutedPayloadEnhancement,
};
pub(in crate::wallet::sync_engine) use queue::queue_stored_transactions;

pub(super) use coordinator::ProductionEnhancementEffects;
