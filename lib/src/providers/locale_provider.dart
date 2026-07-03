import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';

/// Locales the app ships translations for. Keep in sync with the ARB files
/// in `lib/l10n/`.
/// Kill switch for the Language feature (`--dart-define=VIZOR_LANGUAGE_ENABLED=false`).
///
/// When disabled the app is pinned to English regardless of the OS locale or
/// any stored preference, and the Language rows/modals are hidden — i.e. the
/// exact pre-i18n behavior. English ARB values are byte-identical to the old
/// hardcoded strings, so disabling restores the previous UI verbatim. The
/// const is tree-shaken from release builds like the other VIZOR_* defines.
const bool kLanguageFeatureEnabled = bool.fromEnvironment(
  'VIZOR_LANGUAGE_ENABLED',
  defaultValue: true,
);

const kEnglishLocale = Locale('en');
const kKoreanLocale = Locale('ko');

/// Holds the user's selected app [Locale], or null when no language has been
/// picked yet.
///
/// Null means "follow the OS locale" (System (Auto)): `MaterialApp.locale`
/// receives null and Flutter resolves the device locale against
/// `supportedLocales`, falling back to English.
class LocaleNotifier extends Notifier<Locale?> {
  static final _store = AppSecureStore.instance;

  @override
  Locale? build() => ref.watch(appBootstrapProvider).locale;

  Future<void> set(Locale locale) async {
    await _store.writePlain(kLocaleKey, locale.languageCode);
    state = locale;
  }

  /// Clears the stored preference so the app follows the OS locale again
  /// (the "System (Auto)" language option).
  Future<void> clearToSystem() async {
    await _store.delete(kLocaleKey);
    state = null;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);

/// Resolves the effective app locale: the user's saved preference, or the
/// OS locale when no preference is stored, clamped to the supported set
/// (English fallback).
///
/// With no preference this walks the full preferred-locale list
/// ([PlatformDispatcher.locales]), not just the primary locale — matching
/// how Flutter resolves `MaterialApp.locale == null` — so provider-produced
/// text ([appLocalizationsProvider]) always agrees with widget text when a
/// user's primary OS language is unsupported but a later one is supported.
Locale resolveAppLocale(Locale? preference, {List<Locale>? systemLocales}) {
  final candidates = preference != null
      ? [preference]
      : systemLocales ?? PlatformDispatcher.instance.locales;
  for (final locale in candidates) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return supported;
      }
    }
  }
  return kEnglishLocale;
}

/// Context-free [AppLocalizations] for providers and services that produce
/// user-facing strings outside the widget tree.
final appLocalizationsProvider = Provider<AppLocalizations>((ref) {
  if (!kLanguageFeatureEnabled) {
    return lookupAppLocalizations(kEnglishLocale);
  }
  Locale? preference;
  try {
    preference = ref.watch(localeProvider);
  } catch (_) {
    // Unit-test containers may not wire appBootstrapProvider (which
    // localeProvider builds from); fall back to the system locale.
    preference = null;
  }
  List<Locale>? systemLocales;
  try {
    systemLocales = ref.watch(platformLocalesProvider);
  } catch (_) {
    // Pure Dart containers without a widgets binding — fall back to a
    // one-shot PlatformDispatcher read inside resolveAppLocale.
    systemLocales = null;
  }
  return lookupAppLocalizations(
    resolveAppLocale(preference, systemLocales: systemLocales),
  );
});

/// The OS preferred-locale list, kept live via [WidgetsBindingObserver] so
/// [appLocalizationsProvider] re-resolves when the device language changes
/// while the app runs in System (Auto) mode — keeping provider-produced
/// strings in agreement with widget text, which Flutter already re-resolves
/// on its own.
final platformLocalesProvider =
    NotifierProvider<_PlatformLocalesNotifier, List<Locale>>(
      _PlatformLocalesNotifier.new,
    );

class _PlatformLocalesNotifier extends Notifier<List<Locale>>
    with WidgetsBindingObserver {
  @override
  List<Locale> build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return PlatformDispatcher.instance.locales;
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    state = List<Locale>.unmodifiable(
      locales ?? PlatformDispatcher.instance.locales,
    );
  }
}
