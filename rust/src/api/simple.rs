#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();

    // Filter out verbose TLS/gRPC debug logs — only show our sync logs
    log::set_max_level(log::LevelFilter::Info);

    // Install the `ring` CryptoProvider as the process-wide default for
    // rustls 0.23+. Without this, the first TLS handshake panics with
    // "no process-level CryptoProvider installed".
    let _ = rustls::crypto::ring::default_provider().install_default();
}
