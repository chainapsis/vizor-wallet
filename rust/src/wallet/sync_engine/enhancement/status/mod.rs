//! Transaction-status source policy.
//!
//! A reader selects exactly one source for its lifetime. When private Status
//! PIR is selected, initialization or observation failure is inconclusive and
//! must not fall back to a public transaction-ID request.

#[path = "../status_pir.rs"]
mod private_pir;

pub(crate) use private_pir::{enabled_for_preference, reader, PrivateStatusSource};
