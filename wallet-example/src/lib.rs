#[cfg(all(feature = "lrz", feature = "zakura"))]
compile_error!("features `lrz` and `zakura` cannot be enabled together");

#[cfg(not(any(feature = "lrz", feature = "zakura")))]
compile_error!("enable exactly one of the `lrz` or `zakura` features");

pub mod example_capability_handoff;
pub mod example_config;
pub mod example_delegation;
pub mod example_recovery;
pub mod example_vote;
pub mod example_wire;
