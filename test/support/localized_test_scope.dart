import 'package:flutter/widgets.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

/// Left-to-right [Directionality] plus app and Material localizations, for
/// tests that pump widgets without a MaterialApp. English by default.
class LocalizedTestScope extends StatelessWidget {
  const LocalizedTestScope({
    required this.child,
    this.locale = const Locale('en'),
    super.key,
  });

  final Widget child;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Localizations(
      locale: locale,
      delegates: appLocalizationsDelegates,
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );
  }
}
