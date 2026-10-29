import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/rpc_endpoint_provider.dart';
import '../../core/config/network_config.dart';
import '../../rust/wallet/ledger.dart' show LedgerAppSupport;

/// What Vizor may ask a connected Ledger Zcash app to do, by app version.
/// Transaction budgets are enforced by Rust `ledger/limits.rs`;
/// see `docs/ledger/limitations.md` for the full support/enforcement map.
///
/// | Version   | New account | Signing | Memo shown as a hash | NU7 branch, Orchard to Ironwood |
/// |-----------|-------------|---------|----------------------|---------------------------------|
/// | < 3.9.3   | refused     | refused | —                    | —                               |
/// | 3.9.3     | refused     | yes     | refused              | refused                         |
/// | 3.9.4     | yes         | yes     | yes                  | refused                         |
/// | >= 3.10.0 | yes         | yes     | yes                  | yes                             |
///
/// The app shows a memo as text only when every byte is printable ASCII, and
/// as a hash otherwise.
///
/// Signing starts at 3.9.3 because Vizor builds transactions to that app's
/// limits. Ledger Wallet still installs older versions on older firmware.
const kMinimumLedgerZcashAppVersion = '3.9.3';

/// Before this version the app crashed while hashing a memo for display, so
/// Vizor refuses to send such a memo to an older app.
const kLedgerMemoHashAppVersion = '3.9.4';

/// Shown when signing is refused because the connected app predates
/// [kLedgerMemoHashAppVersion]. Keep this identical to
/// `LEDGER_MEMO_HASH_UNSUPPORTED` in `rust/src/wallet/ledger/parse.rs`, which is
/// the error Rust returns and `ledgerFailureGuidance` matches on.
const ledgerMemoHashUnsupportedError =
    'Update the Ledger Zcash app to sign non-English memos';

/// Before this version the app rejects the NU7 consensus branch and an Orchard
/// spend into Ironwood, and Ledger Wallet offers it only on each device's
/// latest firmware.
const kLedgerNu7AppVersion = '3.10.0';

/// Shown when Rust refuses either for an older app. Keep this identical to
/// `LEDGER_APP_UPDATE_REQUIRED` in `rust/src/wallet/ledger/parse.rs`.
const ledgerAppUpdateRequiredError =
    'Update your Ledger and its Zcash app to $kLedgerNu7AppVersion or newer '
    'in Ledger Wallet.';

/// Accounts connected from now on start without the 3.9.3 memo limit; those
/// connected earlier keep signing from [kMinimumLedgerZcashAppVersion].
const kMinimumLedgerZcashAppVersionForNewAccounts = kLedgerMemoHashAppVersion;

/// Ledger's device-review budget, shared by the supported 3.9.3 to 3.10.0 apps.
/// This is independent of the 32-action budget per shielded pool: internal
/// change is excluded, external Orchard and Ironwood outputs are combined.
/// Rust enforces it when preparing a Gift Card batch. See
/// `docs/ledger/limitations.md` for all constraints.
const kLedgerMaxExternalShieldedOutputs = 4;

bool ledgerAppVersionAllowsNewAccounts(String appVersion) =>
    _atLeast(appVersion, kMinimumLedgerZcashAppVersionForNewAccounts);

/// Whether the app at `appVersion` can show a memo as a hash. Callers pass this
/// into the Rust signing entry points, which hold the memo bytes; an unknown
/// version fails closed.
bool ledgerSupportsMemoHash(String? appVersion) =>
    appVersion != null && _atLeast(appVersion, kLedgerMemoHashAppVersion);

bool ledgerSupportsNu7Branch(String? appVersion) =>
    appVersion != null && _atLeast(appVersion, kLedgerNu7AppVersion);

/// What the Rust signing entry points may send to the app at `appVersion`.
LedgerAppSupport ledgerAppSupport(String? appVersion) {
  final fromNu7App = ledgerSupportsNu7Branch(appVersion);
  return LedgerAppSupport(
    memoHash: ledgerSupportsMemoHash(appVersion),
    nu7Branch: fromNu7App,
    orchardToIronwood: fromNu7App,
  );
}

/// A Ledger account can recover legacy Orchard funds when the same seed was
/// previously used through another wallet or Ledger Zcash app build.
///
/// Keep this as an explicit capability boundary so the preserved migration
/// signer can be re-enabled deliberately after a future Ledger app is verified
/// against the migration canary.
const ledgerAutomaticOrchardMigrationCapability = LedgerCapability.unsupported(
  'Automatic Orchard migration is not available for Ledger accounts.',
);

bool isLedgerMemoHashUnsupported(Object error) =>
    error.toString().contains(ledgerMemoHashUnsupportedError);

bool isLedgerAppUpdateRequired(Object error) =>
    error.toString().contains(ledgerAppUpdateRequiredError);

enum LedgerBluetoothCapability { supported, unsupported, unknown }

LedgerBluetoothCapability ledgerBluetoothCapabilityForModel(String? model) {
  final normalized = (model ?? '').toLowerCase().replaceAll(
    RegExp('[^a-z0-9]'),
    '',
  );
  if (normalized.isEmpty) return LedgerBluetoothCapability.unknown;
  if (normalized.contains('nanox') ||
      normalized.contains('stax') ||
      normalized.contains('flex') ||
      normalized.contains('nanogen5') ||
      normalized.contains('nanogeneration5') ||
      normalized.contains('apex')) {
    return LedgerBluetoothCapability.supported;
  }
  if (normalized.contains('nanos') || normalized.contains('nanosplus')) {
    return LedgerBluetoothCapability.unsupported;
  }
  return LedgerBluetoothCapability.unknown;
}

LedgerBluetoothCapability ledgerBluetoothTransportCapabilityForModel({
  required String? model,
  required TargetPlatform platform,
}) {
  if (!ledgerSupportsBluetooth(platform)) {
    return LedgerBluetoothCapability.unsupported;
  }
  final hardware = ledgerBluetoothCapabilityForModel(model);
  if (hardware != LedgerBluetoothCapability.supported) return hardware;
  return LedgerBluetoothCapability.supported;
}

String ledgerBluetoothSupportedModels(TargetPlatform platform) =>
    'Nano X, Flex, Stax, and Nano Gen5';

class LedgerCapability {
  const LedgerCapability._({required this.supported, this.reason});

  const LedgerCapability.supported() : this._(supported: true);

  const LedgerCapability.unsupported(String reason)
    : this._(supported: false, reason: reason);

  final bool supported;
  final String? reason;

  void requireSupported() {
    if (!supported) {
      throw UnsupportedError(
        reason ?? 'Ledger is not supported in this build.',
      );
    }
  }
}

LedgerCapability ledgerStaticCapability({
  required TargetPlatform platform,
  required String networkName,
}) {
  if (!ledgerSupportsUsb(platform) && !isLedgerMobilePlatform(platform)) {
    return const LedgerCapability.unsupported(
      'Ledger is supported on Vizor for macOS, Windows, Linux, iOS, and Android.',
    );
  }
  if (zcashNetworkFromName(networkName) != ZcashNetwork.mainnet) {
    return const LedgerCapability.unsupported(
      'Ledger is currently supported only for Zcash mainnet.',
    );
  }
  return const LedgerCapability.supported();
}

bool ledgerSupportsUsb(TargetPlatform platform) =>
    platform == TargetPlatform.macOS ||
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.linux;

bool ledgerSupportsBluetooth(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || isLedgerMobilePlatform(platform);

bool isLedgerMobilePlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.android;

void requireSupportedLedgerAppVersion(String version) {
  if (!_atLeast(version, kMinimumLedgerZcashAppVersion)) {
    throw UnsupportedError(
      'Update the Ledger Zcash app to version '
      '$kMinimumLedgerZcashAppVersion or newer.',
    );
  }
}

final ledgerTargetPlatformProvider = Provider<TargetPlatform>(
  (_) => defaultTargetPlatform,
);

final ledgerStaticCapabilityProvider = Provider<LedgerCapability>((ref) {
  final platform = ref.watch(ledgerTargetPlatformProvider);
  final networkName = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );
  return ledgerStaticCapability(platform: platform, networkName: networkName);
});

bool _atLeast(String version, String minimum) {
  final parsed = _parseVersion(version);
  return parsed != null &&
      _compareVersion(parsed, _parseVersion(minimum)!) >= 0;
}

({int major, int minor, int patch})? _parseVersion(String value) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(value.trim());
  if (match == null) return null;
  return (
    major: int.parse(match.group(1)!),
    minor: int.parse(match.group(2)!),
    patch: int.parse(match.group(3)!),
  );
}

int _compareVersion(
  ({int major, int minor, int patch}) left,
  ({int major, int minor, int patch}) right,
) {
  final major = left.major.compareTo(right.major);
  if (major != 0) return major;
  final minor = left.minor.compareTo(right.minor);
  if (minor != 0) return minor;
  return left.patch.compareTo(right.patch);
}
