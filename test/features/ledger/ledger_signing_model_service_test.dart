import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);

  for (final compact in [false, true]) {
    test(
      'USB ${compact ? "action" : "full"} signer publishes model with first sending event',
      () async {
        final c = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            ledgerStaticCapabilityProvider.overrideWithValue(
              const LedgerCapability.supported(),
            ),
            ledgerWalletDbPathProvider.overrideWithValue(
              () async => '/fixture.db',
            ),
            ledgerConnectionServiceProvider.overrideWith(_UsbConnection.new),
          ],
        );
        addTearDown(c.dispose);
        final observed = <LedgerSigningProgress>[];
        c.listen(ledgerSigningProgressProvider, (_, value) {
          if (value != null) observed.add(value);
        });
        Future<void> sign() async {
          if (compact) {
            await c.read(ledgerActionPcztSignerProvider)('account', [1]);
          } else {
            await c.read(ledgerPcztTransportSignerProvider)('account', [1]);
          }
        }

        api.model = 'stax';
        await sign();
        expect(api.compact, compact);
        final sending = observed
            .where((p) => p.stage == LedgerSigningStage.sending)
            .single;
        expect(sending.deviceModel, 'stax');
        expect(c.read(ledgerSigningProgressProvider)?.deviceModel, 'stax');
        expect(
          c.read(ledgerSigningProgressProvider)?.stage,
          LedgerSigningStage.finishing,
        );

        observed.clear();
        api.model = null;
        await sign();
        expect(
          observed.every((p) => p.deviceModel == null),
          isTrue,
          reason:
              'A later USB connection must not inherit the preceding Stax model.',
        );
      },
    );
  }

  for (final compact in [false, true]) {
    for (final (version, supported) in [('3.9.3', false), ('3.9.4', true)]) {
      test('USB ${compact ? "action" : "full"} signer tells Rust whether '
          'app $version can show a memo hash', () async {
        final c = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            ledgerStaticCapabilityProvider.overrideWithValue(
              const LedgerCapability.supported(),
            ),
            ledgerWalletDbPathProvider.overrideWithValue(
              () async => '/fixture.db',
            ),
            ledgerConnectionServiceProvider.overrideWith(
              (ref) => _ReadyUsbConnection(ref, version),
            ),
          ],
        );
        addTearDown(c.dispose);
        api.memoHashSupported = null;
        if (compact) {
          await c.read(ledgerActionPcztSignerProvider)('account', [1]);
        } else {
          await c.read(ledgerPcztTransportSignerProvider)('account', [1]);
        }
        expect(api.memoHashSupported, supported);
      });
    }
  }
}

/// Publishes app readiness before the transport callback, as the real service
/// does, so the signer reads the version the connection just verified.
class _ReadyUsbConnection extends LedgerConnectionService {
  _ReadyUsbConnection(this._readyRef, this._version) : super(_readyRef);

  final Ref _readyRef;
  final String _version;

  @override
  Future<T> run<T>({
    required String accountUuid,
    required Future<T> Function() usb,
    required Future<T> Function(LedgerMobileBleService mobile) bluetooth,
    void Function(LedgerBleDevice device)? onBluetoothConnected,
  }) {
    _readyRef
        .read(ledgerAppReadinessStateProvider.notifier)
        .update(LedgerAppReadinessState.ready(_version));
    return usb();
  }
}

class _UsbConnection extends LedgerConnectionService {
  _UsbConnection(super.ref);

  @override
  Future<T> run<T>({
    required String accountUuid,
    required Future<T> Function() usb,
    required Future<T> Function(LedgerMobileBleService mobile) bluetooth,
    void Function(LedgerBleDevice device)? onBluetoothConnected,
  }) => usb();
}

class _Api extends RustLibApi {
  String? model;
  bool? compact;
  bool? memoHashSupported;

  @override
  Stream<LedgerSigningEvent> crateApiLedgerLedgerSignWithProgress({
    required String dbPath,
    required String accountUuid,
    required List<int> pcztBytes,
    required String network,
    required bool compact,
    required bool memoHashSupported,
  }) {
    this.compact = compact;
    this.memoHashSupported = memoHashSupported;
    return Stream.fromIterable([
      LedgerSigningEvent(
        phase: 'sending',
        deviceModel: model,
        signatures: const [],
      ),
      const LedgerSigningEvent(phase: 'reviewing', signatures: []),
      const LedgerSigningEvent(phase: 'finishing', signatures: []),
      LedgerSigningEvent(
        phase: 'complete',
        signedPczt: Uint8List.fromList([2]),
        signatures: const [],
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
