import 'dart:async';
import '../src/providers/rpc_endpoint_provider.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/features/ledger/services/ledger_connection_service.dart';
import '../src/features/ledger/services/ledger_signing_progress.dart';
import '../src/features/ledger/widgets/ledger_signing_modal.dart';
// Deterministic recovery interactions: no wallet data, Rust, or native IO.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/ledger/ledger_capability.dart';
import '../src/features/ledger/services/ledger_account_service.dart';
import '../src/features/ledger/services/ledger_bluetooth_access.dart';
import '../src/features/ledger/services/ledger_mobile_ble_service.dart';
import '../src/features/ledger/services/ledger_pairing_recovery_service.dart';
import '../src/features/ledger/services/ledger_signing_service.dart';
import '../src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import '../src/features/ledger/widgets/mobile_ledger_signing_surface.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';

const _account = AccountInfo(
  uuid: 'capture',
  name: 'Ledger',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  zip32AccountIndex: 0,
  ledgerConnectionPreference: LedgerConnectionPreference.bluetooth,
  ledgerDeviceId: 'flex',
  ledgerDeviceModel: 'Flex',
);

Widget buildLedgerRePairingCapture(BuildContext context) =>
    _buildCapture(context);
Widget buildLedgerDeviceSelectionCapture(BuildContext context) =>
    _buildCapture(context, selectFirst: true);
Widget buildLedgerKnownDeviceConnectingCapture(BuildContext context) =>
    _buildCapture(context, selectFirst: true, holdReadiness: true);
Widget _buildCapture(
  BuildContext context, {
  bool selectFirst = false,
  bool holdReadiness = false,
}) {
  final mobile = kAppFormFactor == AppFormFactor.mobile;
  final Widget modal = selectFirst
      ? const _SelectionCaptureHost()
      : const LedgerAccessRecoveryModal(
          account: _account,
          pairingRecovery: true,
          onRetry: _noop,
          onClose: _noop,
        );
  return ProviderScope(
    overrides: [
      rpcEndpointProvider.overrideWith(_Rpc.new),
      accountProvider.overrideWith(_Accounts.new),
      appSecurityProvider.overrideWith(_Security.new),
      ledgerTargetPlatformProvider.overrideWithValue(
        mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      ledgerMobileBleServiceProvider.overrideWithValue(
        _Ble(holdReadiness: holdReadiness),
      ),
      ledgerRecoveryAccountKeyLoaderProvider.overrideWithValue(
        (_) async => 'expected',
      ),
      ledgerBluetoothAccountConnectorProvider.overrideWithValue(
        (index, device) async => LedgerDeviceAccount(
          ufvk: device.id == 'other-account' ? 'different' : 'expected',
          seedFingerprint: const [],
          accountIndex: index,
          appVersion: '1',
        ),
      ),
      ledgerRustOperationCancellerProvider.overrideWithValue(() async {}),
    ],
    child: mobile
        ? MobileLedgerSigningSurface(
            title: 'Confirm transaction',
            onBack: _noop,
            canLeave: true,
            child: modal,
          )
        : ColoredBox(
            color: context.colors.background.window,
            child: Center(child: modal),
          ),
  );
}

void _noop() {}

class _Accounts extends AccountNotifier {
  @override
  AccountState build() =>
      const AccountState(accounts: [_account], activeAccountUuid: 'capture');
  @override
  Future<void> recordLedgerConnection({
    required String uuid,
    required LedgerConnectionTransport transport,
    String? deviceId,
    String? deviceName,
    String? deviceModel,
  }) async {}
  @override
  Future<void> updateLedgerConnectionPreference(
    String uuid,
    LedgerConnectionPreference preference,
  ) async {}
}

class _Ble
    implements
        LedgerMobileBleService,
        LedgerBluetoothAccess,
        LedgerBluetoothPairingSettings {
  _Ble({bool holdReadiness = false})
    : _readiness = holdReadiness ? Completer<void>() : null;
  final Completer<void>? _readiness;
  @override
  String? connectedDeviceId;
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    await _readiness?.future;
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');
  }

  @override
  Future<void> disconnect() async {
    connectedDeviceId = null;
  }

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectedDeviceId = device.id;
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => Stream.fromIterable(const [
    LedgerDevicesDiscovered([
      LedgerBleDevice(id: 'flex', name: 'Ledger Flex', model: 'Flex'),
      LedgerBleDevice(id: 'nano', name: 'Ledger Nano X', model: 'Nano X'),
      LedgerBleDevice(id: 'other-account', name: 'Ledger Stax', model: 'Stax'),
    ]),
    LedgerDiscoveryEnded(),
  ]);
  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async =>
      const LedgerBluetoothAccessStatus(LedgerBluetoothPermission.granted);
  @override
  Future<bool> openBluetoothPairingSettings() async => true;
  @override
  Future<bool> openBluetoothSettings() async => true;
  @override
  Future<void> cancelSigning() async {
    if (_readiness?.isCompleted == false) _readiness!.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected capture IO: ${invocation.memberName}');
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _Rpc extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
}

class _SelectionCaptureHost extends ConsumerStatefulWidget {
  const _SelectionCaptureHost();
  @override
  ConsumerState<_SelectionCaptureHost> createState() =>
      _SelectionCaptureHostState();
}

class _SelectionCaptureHostState extends ConsumerState<_SelectionCaptureHost> {
  final _signing = Completer<void>();
  var _reviewing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(ledgerConnectionServiceProvider)
            .run<void>(
              accountUuid: _account.uuid,
              usb: () async {},
              bluetooth: (_) {
                if (mounted) setState(() => _reviewing = true);
                return _signing.future;
              },
            )
            .catchError((Object _) {}),
      );
    });
  }

  @override
  void dispose() {
    if (!_signing.isCompleted) _signing.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LedgerSigningModal(
    phase: LedgerSigningModalPhase.awaitingDevice,
    failure: null,
    signingStage: _reviewing
        ? LedgerSigningStage.reviewing
        : LedgerSigningStage.preparing,
    accountUuid: _account.uuid,
    onCancel: _noop,
    onFailureAction: null,
  );
}
