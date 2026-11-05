// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String languageSystemOption(String language) {
    return '시⁠스⁠템 ($language)';
  }

  @override
  String get settingsLanguageLabel => '언⁠어';
}
