pub mod keystone;
pub mod ledger;
pub mod network_privacy;
pub mod pir_config;
pub mod secret;
pub mod simple;
pub mod sync;
pub mod voting;
pub mod voting_session;
pub mod wallet;
pub mod balance_cache;

mod voting_helpers;

pub use crate::api::voting as voting_config;

pub mod gift_card_tracking;

/// Format caught panic payloads once across the generic API guards.
#[cold]
fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    let message = if let Some(message) = payload.downcast_ref::<&str>() {
        message.to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "Unknown panic".to_string()
    };
    format!("Rust panic: {message}")
}
