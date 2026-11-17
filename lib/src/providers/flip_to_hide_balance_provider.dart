import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';

/// Flip to hide (mobile): whether turning the phone screen-down hides
/// amounts, as `FlipToHideBalanceHost` does. On unless turned off in
/// Settings.
class FlipToHideBalanceNotifier extends Notifier<bool> {
  static final _store = AppSecureStore.instance;

  @override
  bool build() => ref.watch(appBootstrapProvider).flipToHideBalanceEnabled;

  Future<void> set(bool enabled) async {
    // Saved as the off flag, so a missing value reads as on.
    await _store.writePlain(
      kFlipToHideBalanceDisabledKey,
      enabled ? 'false' : 'true',
    );
    state = enabled;
  }
}

final flipToHideBalanceProvider =
    NotifierProvider<FlipToHideBalanceNotifier, bool>(
      FlipToHideBalanceNotifier.new,
    );
