import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/l10n/app_language.dart';
import '../core/storage/app_secure_store.dart';

/// Holds the user's language preference; `null` follows the device.
///
/// Like the theme mode, it is read before the first frame and stays readable
/// while the wallet is locked. `MaterialApp` resolves it through
/// [appLocaleFor].
class AppLanguageNotifier extends Notifier<AppLanguage?> {
  static final _store = AppSecureStore.instance;

  @override
  AppLanguage? build() => ref.watch(appBootstrapProvider).appLanguage;

  Future<void> set(AppLanguage? language) async {
    await _store.writePlain(
      kAppLanguageKey,
      encodeAppLanguagePreference(language),
    );
    state = language;
  }
}

final appLanguageProvider = NotifierProvider<AppLanguageNotifier, AppLanguage?>(
  AppLanguageNotifier.new,
);
