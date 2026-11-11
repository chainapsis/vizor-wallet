import 'package:flutter/foundation.dart' show TargetPlatform;

import '../l10n/l10n.dart';

/// Shared private queries description for every platform's settings.
String privateQueriesSettingsCopy(AppLocalizations l10n) =>
    l10n.settingsPrivateQueriesCopy;

/// The private queries description for mobile settings on [platform]. On iOS
/// it adds that background migration tracking cannot run privately, so it
/// stays off while private queries is on.
String privateQueriesMobileSettingsCopy(
  AppLocalizations l10n,
  TargetPlatform platform,
) => platform == TargetPlatform.iOS
    ? '${l10n.settingsPrivateQueriesCopy} ${l10n.settingsPrivateQueriesIosNote}'
    : l10n.settingsPrivateQueriesCopy;
