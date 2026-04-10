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
    log('tor: toggle -> $enabled, stopping sync so next run uses new transport');
    ref.read(syncProvider.notifier).stopSync();
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
/// A failure inside this function is deliberately swallowed and
/// logged — Tor init problems should not prevent the app from
/// launching. If the user later tries to enable Tor from the settings
/// screen while the path is broken, `open_lwd_channel` will surface
/// a clear error on the next sync attempt.
Future<void> initTorAtStartup() async {
  try {
    final base = await getApplicationSupportDirectory();
    final torDir = '${base.path}${Platform.pathSeparator}tor';
    rust_sync.setTorDir(torDir: torDir);
    log('tor: dir=$torDir');

    const storage = FlutterSecureStorage();
    final persisted = await storage.read(key: _torEnabledKey);
    final enabled = persisted == '1';
    rust_sync.setTorEnabled(enabled: enabled);
    log('tor: restored enabled=$enabled');
  } catch (e, st) {
    log('tor: startup init failed: $e\n$st');
  }
}
