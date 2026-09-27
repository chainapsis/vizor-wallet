//! Transaction-status source policy.
//!
//! A reader selects exactly one source for its lifetime. When private Status
//! PIR is selected, initialization or observation failure is inconclusive and
//! must not fall back to a public transaction-ID request.

mod status_private_pir;

pub(crate) use status_private_pir::{enabled_for_preference, reader, PrivateStatusSource};
