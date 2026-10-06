// The PIR transport's nested async types exceed the default layout query depth.
#![recursion_limit = "256"]

pub mod api;
pub mod ffi;
mod frb_generated;
pub mod migration_preparation;
pub mod network_privacy;
mod tor_update_relay;
pub mod wallet;
