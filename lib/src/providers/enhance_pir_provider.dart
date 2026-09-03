import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';
import '../rust/api/sync.dart' as rust_sync;
import 'sync_provider.dart';

class EnhancePirNotifier extends Notifier<bool> {
  static final _store = AppSecureStore.instance;

  @override
  bool build() => ref.watch(appBootstrapProvider).enhancePirEnabled;

  Future<void> set(bool enabled) async {
    await _store.writePlain(kEnhancePirEnabledKey, enabled ? 'true' : 'false');
    rust_sync.setEnhancePirEnabled(enabled: enabled);
    state = enabled;
    await ref.read(syncProvider.notifier).restartSync();
  }

  Future<void> toggle() => set(!state);
}

final enhancePirProvider = NotifierProvider<EnhancePirNotifier, bool>(
  EnhancePirNotifier.new,
);
