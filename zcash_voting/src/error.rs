//! Public error surface for wallet integrations.
//!
//! The voting API uses one error type across setup, precompute, delegation, and
//! persistence operations. Re-exporting it from this module gives downstream
//! SDKs a stable import path even as internal modules move.

pub use crate::types::VotingError;
