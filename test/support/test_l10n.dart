import 'dart:ui' show Locale;

import 'package:zcash_wallet/src/core/l10n/l10n.dart';

/// English strings for tests that call l10n-taking functions directly,
/// outside a widget tree.
final testL10n = lookupAppLocalizations(const Locale('en'));
