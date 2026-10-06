//! Auxiliary transaction metadata recovered after compact-block scanning.
//!
//! These lanes do not select public or private status/payload policy. The
//! parent enhancement session controls their ordering around those flows.

pub(super) mod fees;
pub(super) mod transparent_history;
