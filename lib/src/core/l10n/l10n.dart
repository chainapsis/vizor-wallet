import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';

export '../../../l10n/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  /// The app strings for the nearest locale. Fails with a pointer to the fix
  /// when a widget tree has no app localizations.
  AppLocalizations get l10n {
    final localizations = Localizations.of<AppLocalizations>(
      this,
      AppLocalizations,
    );
    if (localizations == null) {
      throw FlutterError(
        'No AppLocalizations found above this widget.\n'
        'Pass appLocalizationsDelegates to the MaterialApp. A test without a '
        'MaterialApp wraps its tree in LocalizedTestScope.',
      );
    }
    return localizations;
  }
}
