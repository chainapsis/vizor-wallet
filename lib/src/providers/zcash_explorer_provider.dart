import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/zcash_explorer.dart';
import '../core/storage/app_secure_store.dart';

class ZcashExplorerNotifier extends Notifier<String> {
  static final _store = AppSecureStore.instance;

  @override
  String build() => ref.watch(appBootstrapProvider).explorerUrlTemplate;

  bool get isCustom => state.trim().isNotEmpty;

  String labelForNetwork(String networkName) {
    return explorerSettingsLabel(state, networkName: networkName);
  }

  Future<void> setCustom(String input) async {
    final normalized = normalizeExplorerUrlTemplate(input);
    await _store.writePlain(kZcashExplorerUrlKey, normalized);
    state = normalized;
  }

  Future<void> resetToDefault() async {
    await _store.delete(kZcashExplorerUrlKey);
    state = '';
  }
}

final zcashExplorerProvider = NotifierProvider<ZcashExplorerNotifier, String>(
  ZcashExplorerNotifier.new,
);
