import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/rpc_endpoint_provider.dart';
import '../../core/config/network_config.dart';

const kMinimumLedgerZcashAppVersion = '3.9.2';

/// Legacy Orchard funds can only come from unreleased Ledger Zcash app builds.
///
/// Keep this as an explicit capability boundary so the preserved migration
/// signer can be re-enabled deliberately after a future Ledger app is verified
/// against the migration canary.
const ledgerAutomaticOrchardMigrationCapability = LedgerCapability.unsupported(
  'Automatic Orchard migration is not available for Ledger accounts.',
);

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
  final hardware = ledgerBluetoothCapabilityForModel(model);
  if (hardware != LedgerBluetoothCapability.supported) return hardware;
  final normalized = (model ?? '').toLowerCase().replaceAll(
    RegExp('[^a-z0-9]'),
    '',
  );
  if ((platform == TargetPlatform.macOS || platform == TargetPlatform.iOS) &&
      (normalized.contains('nanogen5') ||
          normalized.contains('nanogeneration5') ||
          normalized.contains('apex'))) {
    return LedgerBluetoothCapability.unsupported;
  }
  return LedgerBluetoothCapability.supported;
}

String ledgerBluetoothSupportedModels(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS
    ? 'Nano X, Flex, and Stax'
    : 'Nano X, Flex, Stax, and Nano Gen5';

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
  if (platform != TargetPlatform.macOS && !isLedgerMobilePlatform(platform)) {
    return const LedgerCapability.unsupported(
      'Ledger is currently supported only on Vizor for macOS, iOS, and Android.',
    );
  }
  if (zcashNetworkFromName(networkName) != ZcashNetwork.mainnet) {
    return const LedgerCapability.unsupported(
      'Ledger is currently supported only for Zcash mainnet.',
    );
  }
  return const LedgerCapability.supported();
}

bool isLedgerMobilePlatform(TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.android;

void requireSupportedLedgerAppVersion(String version) {
  final parsed = _parseVersion(version);
  final minimum = _parseVersion(kMinimumLedgerZcashAppVersion)!;
  if (parsed == null || _compareVersion(parsed, minimum) < 0) {
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
