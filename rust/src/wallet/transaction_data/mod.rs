//! Transaction observation and payload retrieval are separate capabilities.
//!
//! Status callers receive observations without transaction bytes. The public
//! lightwalletd adapter still fetches and validates a payload on the wire.
pub(crate) mod payload;
mod status;

pub(crate) use status::{LookupError, TransactionObservation};
