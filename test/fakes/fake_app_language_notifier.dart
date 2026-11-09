import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/providers/app_language_provider.dart';

/// Records language choices instead of writing secure storage.
class FakeAppLanguageNotifier extends AppLanguageNotifier {
  FakeAppLanguageNotifier(this.saved);

  final List<AppLanguage> saved;

  @override
  AppLanguage build() => AppLanguage.en;

  @override
  Future<void> set(AppLanguage language) async {
    saved.add(language);
    state = language;
  }
}

/// Offers every language, as a `VIZOR_I18N_PREVIEW` build does, and records
/// choices in [saved].
List<Override> languagePreviewOverrides(List<AppLanguage> saved) => [
  availableAppLanguagesProvider.overrideWithValue(AppLanguage.values),
  appLanguageProvider.overrideWith(() => FakeAppLanguageNotifier(saved)),
];
