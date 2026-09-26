//! Auxiliary transaction metadata recovered after compact-block scanning.
//!
//! One invocation performs fee backfill, status observation, and transparent
//! address history in that order. Payload requests are intentionally ignored;
//! only the payload package may execute the wallet's routed payload snapshot.

#[path = "../transaction_requests.rs"]
mod coordinator;
#[path = "../fees.rs"]
pub(super) mod fees;
mod status;
mod transparent_history;

pub(in crate::wallet::sync_engine) use coordinator::run_auxiliary_transaction_requests;
