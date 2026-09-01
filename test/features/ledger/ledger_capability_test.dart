import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';

void main() {
  test('supports macOS, iOS, and Android mainnet only', () {
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.android,
        networkName: 'main',
      ).supported,
      isTrue,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.macOS,
        networkName: 'main',
      ).supported,
      isTrue,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.macOS,
        networkName: 'test',
      ).supported,
      isFalse,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.iOS,
        networkName: 'main',
      ).supported,
      isTrue,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.windows,
        networkName: 'main',
      ).supported,
      isFalse,
    );
  });

  test('identifies the native mobile Ledger platforms', () {
    expect(isLedgerMobilePlatform(TargetPlatform.iOS), isTrue);
    expect(isLedgerMobilePlatform(TargetPlatform.android), isTrue);
    expect(isLedgerMobilePlatform(TargetPlatform.macOS), isFalse);
  });

  test('accepts the minimum and newer Ledger Zcash app versions', () {
    expect(() => requireSupportedLedgerAppVersion('3.9.2'), returnsNormally);
    expect(() => requireSupportedLedgerAppVersion('3.10.0'), returnsNormally);
    expect(() => requireSupportedLedgerAppVersion('4.0.0'), returnsNormally);
  });

  test('rejects old or malformed Ledger Zcash app versions', () {
    expect(
      () => requireSupportedLedgerAppVersion('3.9.1'),
      throwsUnsupportedError,
    );
    expect(
      () => requireSupportedLedgerAppVersion('unknown'),
      throwsUnsupportedError,
    );
  });

  test('quarantines legacy Orchard migration for Ledger', () {
    expect(ledgerAutomaticOrchardMigrationCapability.supported, isFalse);
    expect(
      ledgerAutomaticOrchardMigrationCapability.reason,
      contains('not available for Ledger accounts'),
    );
  });

  test('classifies Bluetooth support from the Ledger model', () {
    for (final model in ['Nano X', 'Ledger Stax', 'Flex', 'Nano Gen5']) {
      expect(
        ledgerBluetoothCapabilityForModel(model),
        LedgerBluetoothCapability.supported,
        reason: model,
      );
    }
    for (final model in ['Nano S', 'Nano S Plus']) {
      expect(
        ledgerBluetoothCapabilityForModel(model),
        LedgerBluetoothCapability.unsupported,
        reason: model,
      );
    }
    expect(
      ledgerBluetoothCapabilityForModel(null),
      LedgerBluetoothCapability.unknown,
    );
  });

  test('applies the current Apple BLE transport model boundary', () {
    expect(
      ledgerBluetoothTransportCapabilityForModel(
        model: 'Nano Gen5',
        platform: TargetPlatform.macOS,
      ),
      LedgerBluetoothCapability.unsupported,
    );
    expect(
      ledgerBluetoothTransportCapabilityForModel(
        model: 'Nano Gen5',
        platform: TargetPlatform.android,
      ),
      LedgerBluetoothCapability.supported,
    );
    expect(
      ledgerBluetoothTransportCapabilityForModel(
        model: 'Ledger Stax',
        platform: TargetPlatform.macOS,
      ),
      LedgerBluetoothCapability.supported,
    );
  });
}
