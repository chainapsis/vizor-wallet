import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';

void main() {
  test('USB product strings become the shared Ledger model name', () {
    expect(ledgerUsbDeviceModelName('Nano S Plus'), 'Ledger Nano S Plus');
    expect(ledgerUsbDeviceModelName(' Ledger Nano X '), 'Ledger Nano X');
    expect(
      ledgerBluetoothCapabilityForModel(
        ledgerUsbDeviceModelName('Nano S Plus'),
      ),
      LedgerBluetoothCapability.unsupported,
    );
    expect(
      ledgerBluetoothCapabilityForModel(ledgerUsbDeviceModelName('Stax')),
      LedgerBluetoothCapability.supported,
    );
  });

  test('supports desktop, iOS, and Android mainnet only', () {
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
      isTrue,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.windows,
        networkName: 'test',
      ).supported,
      isFalse,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.linux,
        networkName: 'main',
      ).supported,
      isTrue,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.linux,
        networkName: 'test',
      ).supported,
      isFalse,
    );
    expect(
      ledgerStaticCapability(
        platform: TargetPlatform.fuchsia,
        networkName: 'main',
      ).supported,
      isFalse,
    );
  });

  test('identifies the native mobile Ledger platforms', () {
    expect(isLedgerMobilePlatform(TargetPlatform.iOS), isTrue);
    expect(isLedgerMobilePlatform(TargetPlatform.android), isTrue);
    expect(isLedgerMobilePlatform(TargetPlatform.macOS), isFalse);
    expect(isLedgerMobilePlatform(TargetPlatform.windows), isFalse);
  });

  test('supports Bluetooth on desktop and mobile platforms only', () {
    for (final platform in TargetPlatform.values) {
      final supported =
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.windows ||
          platform == TargetPlatform.linux ||
          platform == TargetPlatform.iOS ||
          platform == TargetPlatform.android;
      expect(
        isLedgerBluetoothPlatform(platform),
        supported,
        reason: '$platform',
      );
      expect(
        ledgerBluetoothTransportCapabilityForModel(
          model: 'Nano X',
          platform: platform,
        ),
        supported
            ? LedgerBluetoothCapability.supported
            : LedgerBluetoothCapability.unsupported,
        reason: '$platform',
      );
    }
  });

  test('accepts the minimum and newer Ledger Zcash app versions', () {
    expect(() => requireSupportedLedgerAppVersion('3.9.3'), returnsNormally);
    expect(() => requireSupportedLedgerAppVersion('3.10.0'), returnsNormally);
    expect(() => requireSupportedLedgerAppVersion('4.0.0'), returnsNormally);
  });

  test('rejects old or malformed Ledger Zcash app versions', () {
    expect(
      () => requireSupportedLedgerAppVersion('3.9.2'),
      throwsUnsupportedError,
    );
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
