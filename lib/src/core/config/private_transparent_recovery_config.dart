import 'package:flutter/foundation.dart' show TargetPlatform;

/// Shared private queries description for every platform's settings.
const kPrivateQueriesSettingsCopy =
    'Experimental. Recovers transparent funds privately, preventing the '
    'server from learning your transparent addresses. Looks up supported '
    'transactions without revealing their IDs to servers.';

/// Appended on iOS: background migration tracking cannot run privately, so
/// it stays off while private queries is on.
const kPrivateQueriesIosMigrationCopy =
    'While on, migration confirmations are checked only when Vizor is open.';

/// The private queries description for mobile settings on [platform].
String privateQueriesMobileSettingsCopy(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
    ? '$kPrivateQueriesSettingsCopy $kPrivateQueriesIosMigrationCopy'
    : kPrivateQueriesSettingsCopy;
