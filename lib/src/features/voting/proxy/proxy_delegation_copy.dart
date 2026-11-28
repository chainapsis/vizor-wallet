/// Proxy delegation copy that code picks from a condition. Plain strings
/// are ARB messages the screens read directly.
library;

import '../../../core/l10n/l10n.dart';

/// How a delegate is named in a sentence: `@handle`.
String proxyDelegateName(String handle) => '@$handle';

/// Why a suspended or retired delegate [name] can't be chosen.
String proxyBlockedCopy(
  AppLocalizations l10n,
  String name, {
  required bool retired,
}) =>
    retired ? l10n.proxyBlockedRetired(name) : l10n.proxyBlockedSuspended(name);
