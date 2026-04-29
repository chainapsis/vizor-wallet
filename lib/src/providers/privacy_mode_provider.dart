import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';

class PrivacyModeNotifier extends Notifier<bool> {
  static final _store = AppSecureStore.instance;

  @override
  bool build() => ref.watch(appBootstrapProvider).privacyModeEnabled;

  Future<void> set(bool enabled) async {
    await _store.writePlain(kPrivacyModeEnabledKey, enabled ? 'true' : 'false');
    state = enabled;
  }

  Future<void> toggle() => set(!state);
}

final privacyModeProvider = NotifierProvider<PrivacyModeNotifier, bool>(
  PrivacyModeNotifier.new,
);
