import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_error_messages.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_wallet_identity_guard.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';

// Stored lowercase, as importLedgerAccount normalises it.
const _fingerprint =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

const _accounts = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'verified',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      ledgerWalletFingerprint: _fingerprint,
    ),
    AccountInfo(
      uuid: 'legacy',
      name: 'Older Ledger import',
      order: 1,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
    ),
  ],
  activeAccountUuid: 'verified',
);

void main() {
  late List<String> reads;
  late String usbFingerprint;
  late String bluetoothFingerprint;
  late ProviderContainer container;

  setUp(() async {
    reads = [];
    usbFingerprint = _fingerprint;
    bluetoothFingerprint = _fingerprint;
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Accounts.new),
        ledgerUsbWalletFingerprintReaderProvider.overrideWithValue((
          network,
        ) async {
          reads.add('usb:$network');
          return usbFingerprint;
        }),
        ledgerBluetoothWalletFingerprintReaderProvider.overrideWithValue((
          mobile,
          network,
        ) async {
          reads.add('bluetooth:${identityHashCode(mobile)}:$network');
          return bluetoothFingerprint;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
  });

  test('a matching wallet passes regardless of hex casing', () async {
    usbFingerprint = _fingerprint.toUpperCase();
    await container.read(ledgerWalletIdentityGuardProvider)('verified');
    final network = container.read(rpcEndpointProvider).networkName;
    expect(reads, ['usb:$network']);
  });

  test('a different wallet fails before any approval', () async {
    usbFingerprint = 'f' * 64;
    await expectLater(
      container.read(ledgerWalletIdentityGuardProvider)('verified'),
      throwsA(isA<LedgerWrongWalletException>()),
    );
    const error = LedgerWrongWalletException();
    expect(error.toString(), kLedgerWrongWalletMessage);
    expect(ledgerActionableErrorMessage(error), kLedgerWrongWalletMessage);
    expect(ledgerRequestNeedsRebuilding(error), isFalse);
  });

  test('an account without a stored fingerprint is not checked', () async {
    await container.read(ledgerWalletIdentityGuardProvider)('legacy');
    await container.read(ledgerWalletIdentityGuardProvider)('unknown');
    expect(reads, isEmpty);
  });

  test('Bluetooth reads the identity on the given connection', () async {
    final mobile = _NoopBleService();
    await container.read(ledgerWalletIdentityGuardProvider)(
      'verified',
      mobile: mobile,
    );
    final network = container.read(rpcEndpointProvider).networkName;
    expect(reads, ['bluetooth:${identityHashCode(mobile)}:$network']);

    bluetoothFingerprint = '0' * 64;
    await expectLater(
      container.read(ledgerWalletIdentityGuardProvider)(
        'verified',
        mobile: mobile,
      ),
      throwsA(isA<LedgerWrongWalletException>()),
    );
  });
}

class _Accounts extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _accounts;
}

class _NoopBleService implements LedgerMobileBleService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
