#[cfg(all(feature = "upstream", feature = "zakura"))]
compile_error!("features `upstream` and `zakura` cannot be enabled together");

#[cfg(not(any(feature = "upstream", feature = "zakura")))]
compile_error!("enable exactly one of the `upstream` or `zakura` features");

mod backend;
pub mod example_capability_handoff;
pub mod example_config;
pub mod example_delegation;
pub mod example_recovery;
pub mod example_vote;
pub mod example_wire;
