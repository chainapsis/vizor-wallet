import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/rust/wallet/ledger.dart' show LedgerAppSupport;

void main() {
  test('desktop USB and mobile BLE are mainnet only', () {
    for (final platform in TargetPlatform.values) {
      final supported = platform != TargetPlatform.fuchsia;
      expect(
        ledgerStaticCapability(
          platform: platform,
          networkName: 'main',
        ).supported,
        supported,
      );
      expect(
        ledgerStaticCapability(
          platform: platform,
          networkName: 'test',
        ).supported,
        isFalse,
      );
    }
  });

  test(
    'Windows and Linux never advertise Bluetooth, even for unknown models',
    () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        expect(ledgerSupportsUsb(platform), isTrue);
        expect(ledgerSupportsBluetooth(platform), isFalse);
        for (final model in [null, 'Nano X', 'Flex', 'Stax', 'Nano Gen5']) {
          expect(
            ledgerBluetoothTransportCapabilityForModel(
              model: model,
              platform: platform,
            ),
            LedgerBluetoothCapability.unsupported,
          );
        }
      }
      expect(ledgerSupportsBluetooth(TargetPlatform.macOS), isTrue);
      expect(ledgerSupportsUsb(TargetPlatform.android), isFalse);
      expect(ledgerSupportsUsb(TargetPlatform.iOS), isFalse);
    },
  );

  test('identifies the native mobile Ledger platforms', () {
    expect(isLedgerMobilePlatform(TargetPlatform.iOS), isTrue);
    expect(isLedgerMobilePlatform(TargetPlatform.android), isTrue);
    expect(isLedgerMobilePlatform(TargetPlatform.macOS), isFalse);
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

  test('new accounts need app 3.9.4 while signing still accepts 3.9.3', () {
    expect(ledgerAppVersionAllowsNewAccounts('3.9.4'), isTrue);
    expect(ledgerAppVersionAllowsNewAccounts('3.10.0'), isTrue);
    expect(ledgerAppVersionAllowsNewAccounts('3.9.3'), isFalse);
    expect(ledgerAppVersionAllowsNewAccounts('unknown'), isFalse);
    expect(() => requireSupportedLedgerAppVersion('3.9.3'), returnsNormally);
  });

  test('memo hashes are supported from app 3.9.4', () {
    for (final version in ['3.9.4', '3.9.10', '3.10.0', '4.0.0']) {
      expect(ledgerSupportsMemoHash(version), isTrue, reason: version);
    }
    // 3.9.3 still signs, but resets the device on a hashed memo.
    for (final version in ['3.9.3', '3.9.2', 'unknown', '', null]) {
      expect(ledgerSupportsMemoHash(version), isFalse, reason: '$version');
    }
  });

  test(
    'the NU7 branch and Orchard to Ironwood are supported from app 3.10.0',
    () {
      for (final version in ['3.10.0', '3.10.1', '3.11.0', '4.0.0']) {
        expect(ledgerSupportsNu7Branch(version), isTrue, reason: version);
      }
      for (final version in ['3.9.4', '3.9.10', '3.9.3', 'unknown', '', null]) {
        expect(ledgerSupportsNu7Branch(version), isFalse, reason: '$version');
      }
      expect(
        ledgerAppSupport('3.10.0'),
        const LedgerAppSupport(
          memoHash: true,
          nu7Branch: true,
          orchardToIronwood: true,
        ),
      );
      expect(
        ledgerAppSupport('3.9.4'),
        const LedgerAppSupport(
          memoHash: true,
          nu7Branch: false,
          orchardToIronwood: false,
        ),
      );
      expect(
        ledgerAppSupport(null),
        const LedgerAppSupport(
          memoHash: false,
          nu7Branch: false,
          orchardToIronwood: false,
        ),
      );
    },
  );

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

  test('offers supported BLE models on Apple and Android', () {
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.android,
    ]) {
      for (final model in ['Nano X', 'Ledger Stax', 'Flex', 'Nano Gen5']) {
        expect(
          ledgerBluetoothTransportCapabilityForModel(
            model: model,
            platform: platform,
          ),
          LedgerBluetoothCapability.supported,
          reason: '$platform $model',
        );
      }
      expect(
        ledgerBluetoothSupportedModels(platform),
        'Nano X, Flex, Stax, and Nano Gen5',
      );
    }
  });
}
