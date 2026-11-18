import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';

/// Flip to hide (mobile): whether turning the phone screen-down hides
/// amounts, as `FlipToHideBalanceHost` does. Off unless turned on in
/// Settings.
class FlipToHideBalanceNotifier extends Notifier<bool> {
  static final _store = AppSecureStore.instance;

  @override
  bool build() => ref.watch(appBootstrapProvider).flipToHideBalanceEnabled;

  Future<void> set(bool enabled) async {
    await _store.writePlain(
      kFlipToHideBalanceEnabledKey,
      enabled ? 'true' : 'false',
    );
    state = enabled;
  }
}

final flipToHideBalanceProvider =
    NotifierProvider<FlipToHideBalanceNotifier, bool>(
      FlipToHideBalanceNotifier.new,
    );
