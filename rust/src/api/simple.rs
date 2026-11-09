#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Instead of `flutter_rust_bridge::setup_default_user_utils()`, which would
    // install an unredacted logger first: same backend and panic backtraces,
    // with identifiers masked.
    crate::log_redaction::install();

    // Filter out verbose TLS/gRPC debug logs — only show our sync logs
    log::set_max_level(log::LevelFilter::Info);

    // Install the `ring` CryptoProvider as the process-wide default for
    // rustls 0.23+. Without this, the first TLS handshake panics with
    // "no process-level CryptoProvider installed".
    let _ = rustls::crypto::ring::default_provider().install_default();
}

/// Keep wallet consensus parameters aligned with the local Ironwood regtest
/// node. Production builds leave the default activation-at-height-1 behavior.
pub fn configure_regtest_ironwood_activation_height(height: u32) -> Result<(), String> {
    crate::wallet::network::configure_regtest_nu6_3_activation_height(height)
}

/// Activates NU7 on regtest at the local node's height. Call after the NU6.3
/// height; production builds leave NU7 inactive on regtest.
pub fn configure_regtest_nu7_activation_height(height: u32) -> Result<(), String> {
    crate::wallet::network::configure_regtest_nu7_activation_height(height)
}

/// Enables Regtest-speed migration timing on Testnet only. Mainnet and
/// Regtest consensus behavior are unaffected.
pub fn configure_fast_testnet_migration(enabled: bool) {
    crate::wallet::sync::configure_fast_testnet_migration(enabled);
}
