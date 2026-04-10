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
    // "no process-level CryptoProvider installed" — rustls refuses to pick
    // a default when multiple providers could plausibly be available.
    //
    // Our graph already pulls in `ring` via tonic's `tls-ring` feature, and
    // with `tor` enabled on zcash_client_backend, arti-client's rustls
    // integration joins the same process. Calling `install_default` once
    // here (discarding the `Err` from a redundant second install if any
    // other code beat us to it) guarantees every TLS path — plain gRPC,
    // gRPC-over-Tor, and the Sapling params HTTP download — resolves to
    // the same provider.
    let _ = rustls::crypto::ring::default_provider().install_default();
}
