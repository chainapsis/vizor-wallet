import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../rust/api/sync.dart' as rust_sync;
import 'sync_provider.dart';

/// Key used to persist the Tor-enabled toggle in flutter_secure_storage.
/// Re-uses the same storage backend the rest of the wallet already depends
/// on for the per-account mnemonics, so there's no extra dep surface.
const _torEnabledKey = 'zcash_tor_enabled';

/// Owns the user-visible "route lightwalletd through Tor" toggle.
///
/// The Rust side already carries the authoritative flag (the `USE_TOR`
/// atomic in `rust/src/api/sync.rs`); this Riverpod notifier is a
/// UI-side mirror that keeps the setting reactive for widgets that
/// want to show or toggle it.
///
/// Startup ordering:
///
///   1. [initTorAtStartup] in `main.dart` runs before `runApp`. It
///      computes `<app_support>/tor`, calls [rust_sync.setTorDir] so
///      the Rust side knows where arti should keep its consensus
///      cache, reads the persisted toggle from secure storage, and
///      calls [rust_sync.setTorEnabled] with that value.
///
///   2. By the time any widget calls [build], the Rust `USE_TOR`
///      atomic already reflects the persisted state, so seeding
///      the notifier with `rust_sync.isTorEnabled()` is correct.
///
///   3. [TorSettingsNotifier.setEnabled] persists the new value to
///      secure storage, calls [rust_sync.setTorEnabled], updates the
///      notifier state for UI reactivity, and stops the current sync
///      so the next `open_lwd_channel` call picks up the new
///      transport. The running sync keeps its existing connection
///      until it's cancelled or finishes — the toggle only affects
///      future connections.
class TorSettingsNotifier extends Notifier<bool> {
  @override
  bool build() => rust_sync.isTorEnabled();

  Future<void> setEnabled(bool enabled) async {
    if (state == enabled) return;
    const storage = FlutterSecureStorage();
    await storage.write(key: _torEnabledKey, value: enabled ? '1' : '0');
    rust_sync.setTorEnabled(enabled: enabled);
    state = enabled;
    log('tor: toggle -> $enabled, restarting sync with new transport');
    // Must be `restartSync`, not a bare `stopSync`. `stopSync` alone
    // leaves the wallet permanently silent if the toggle fires while
    // sync is idle between polls — there's no auto-restart path for
    // that case. `restartSync` stops the current run (if any), waits
    // for the Rust loop to finish tearing down, and immediately
    // starts a fresh run with the new transport.
    //
    // Fire-and-forget: the lifecycle of `setEnabled` is a setting
    // toggle, not a "wait for sync to be healthy" operation. Errors
    // inside `restartSync` already log themselves.
    unawaited(ref.read(syncProvider.notifier).restartSync());
  }
}

final torSettingsProvider = NotifierProvider<TorSettingsNotifier, bool>(
  TorSettingsNotifier.new,
);

/// Call this from `main.dart` before `runApp`. Creates the Tor cache
/// directory on disk (no-op if it already exists), pushes its path
/// into the Rust side via [rust_sync.setTorDir], and restores the
/// persisted toggle state via [rust_sync.setTorEnabled].
///
/// ## Failure handling
///
/// The directory setup and the preference read are handled in two
/// separate try/catch blocks. Errors inside each are logged but do
/// not crash the app — Tor init problems must not block the user
/// from launching the wallet.
///
/// The preference restore is **fail-closed for privacy**. If
/// `FlutterSecureStorage.read` throws (keychain not ready on a cold
/// boot, a platform channel hiccup, Keystore exception, etc.) we
/// default `enabled = true` rather than letting it silently fall
/// back to `false`. A user who previously opted into Tor would
/// otherwise get their privacy downgraded to clearnet on any
/// transient read failure, and the first sync that followed would
/// auto-start over plain gRPC before the user had a chance to
/// notice.
///
/// Users who never opted into Tor take a one-launch bootstrap
/// penalty in the rare case where the read fails on a fresh install
/// — that's an acceptable cost for not silently leaking IPs to
/// lightwalletd operators.
///
/// If `getApplicationSupportDirectory` fails, we intentionally skip
/// the `setTorDir` call and still attempt to restore the toggle.
/// That way, when the next sync runs, `open_lwd_channel` surfaces
/// the "Tor enabled but TOR_DIR not set" error explicitly rather
/// than silently routing over clearnet.
Future<void> initTorAtStartup() async {
  // Step 1: Tor cache directory. Best-effort; failure here doesn't
  // block the preference restore below.
  try {
    final base = await getApplicationSupportDirectory();
    final torDir = '${base.path}${Platform.pathSeparator}tor';
    rust_sync.setTorDir(torDir: torDir);
    log('tor: dir=$torDir');
  } catch (e, st) {
    log('tor: dir setup failed (will still restore toggle): $e\n$st');
  }

  // Step 2: persisted preference. Fail-closed to `enabled = true` so
  // a transient storage failure can't silently downgrade Tor to
  // clearnet on an opted-in user's session.
  const storage = FlutterSecureStorage();
  bool enabled;
  try {
    final persisted = await storage.read(key: _torEnabledKey);
    enabled = persisted == '1';
    log('tor: restored enabled=$enabled');
  } catch (e, st) {
    log('tor: preference read failed, fail-closed to enabled=true for '
        'privacy (was: ${e.runtimeType}): $e\n$st');
    enabled = true;
  }
  rust_sync.setTorEnabled(enabled: enabled);
}
