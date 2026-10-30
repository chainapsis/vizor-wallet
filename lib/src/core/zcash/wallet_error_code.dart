import '../../rust/api/sync.dart' as rust_sync;

/// What Rust says to do about [error] beyond showing its message, or `null`
/// when [error] is not a coded wallet failure.
///
/// Retry and discard decisions read this code, never the message text, so
/// rewording a Rust message cannot change them.
rust_sync.ApiWalletErrorCode? walletErrorCode(Object error) =>
    error is rust_sync.ApiWalletError ? error.code : null;
