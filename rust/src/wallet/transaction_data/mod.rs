//! Transaction observation and payload retrieval are separate capabilities.
//!
//! Status callers receive observations without transaction bytes. The public
//! lightwalletd adapter still fetches and validates a payload on the wire.
//! Public payload retrieval lives behind the sync engine's transparent lookup
//! gate, since `GetTransaction` discloses the txid.
mod status;

pub(crate) use status::{LookupError, TransactionObservation};
