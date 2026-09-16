import 'dart:developer' show log;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../ledger_capability.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_device_request.dart';
import 'ledger_diagnostics.dart';
import 'ledger_mobile_ble_service.dart';
import 'ledger_signing_status_gate.dart';

class LedgerConnectionRequiredException implements Exception {
  const LedgerConnectionRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

final ledgerConnectionServiceProvider = Provider<LedgerConnectionService>(
  LedgerConnectionService.new,
);

class LedgerConnectionService {
  LedgerConnectionService(this._ref);

  final Ref _ref;
  bool _running = false;
  bool _requiresReconnect = false;

  Future<T> run<T>({
    required String accountUuid,
    required Future<T> Function() usb,
    required Future<T> Function(LedgerMobileBleService mobile) bluetooth,
  }) async {
    if (_running) {
      throw const LedgerMobileException(
        LedgerMobileFailure.busy,
        'Another Ledger operation is still active.',
      );
    }
    _running = true;
    try {
      return await _run(
        accountUuid: accountUuid,
        usb: usb,
        bluetooth: bluetooth,
      );
    } finally {
      _running = false;
    }
  }

  Future<T> _run<T>({
    required String accountUuid,
    required Future<T> Function() usb,
    required Future<T> Function(LedgerMobileBleService mobile) bluetooth,
  }) async {
    final check = _ref.read(ledgerDeviceRequestsProvider).capture();
    final account = _account(accountUuid);
    final candidates = _candidates(account);
    Object? lastConnectionError;

    for (final transport in candidates) {
      check();
      ledgerTrace('connection_start transport=${transport.name}');
      var operationStarted = false;
      try {
        final result = switch (transport) {
          LedgerConnectionTransport.usb => await _runUsb(check, () {
            ledgerTrace('connection_ready transport=${transport.name}');
            operationStarted = true;
            return usb();
          }),
          LedgerConnectionTransport.bluetooth => await _runBluetooth(
            check,
            account,
            (mobile) {
              ledgerTrace('connection_ready transport=${transport.name}');
              operationStarted = true;
              return bluetooth(mobile);
            },
          ),
        };
        check();
        try {
          await _recordSuccess(account, transport);
        } catch (error, stackTrace) {
          log(
            'Failed to persist the successful Ledger transport.',
            name: 'LedgerConnectionService',
            error: error,
            stackTrace: stackTrace,
          );
        }
        check();
        return result;
      } catch (error) {
        if (transport == LedgerConnectionTransport.bluetooth &&
            ((error is LedgerMobileException &&
                    ledgerFailureInvalidatesConnection(error.failure)) ||
                (error is LedgerAppReadinessException &&
                    (error.failure == LedgerAppReadinessFailure.disconnected ||
                        error.failure ==
                            LedgerAppReadinessFailure.unavailable)))) {
          _requiresReconnect = true;
        }
        ledgerTrace(
          'connection_error transport=${transport.name} operation_started=$operationStarted type=${error.runtimeType}',
        );
        check();
        // Only connection preparation may fall back; never replay an operation.
        if (operationStarted) rethrow;
        if (!_isConnectionFailure(error)) rethrow;
        if (!ledgerPairingNeedsReset(lastConnectionError)) {
          lastConnectionError = error;
        }
      }
    }

    throw LedgerConnectionRequiredException(
      _connectionFailureMessage(account, lastConnectionError),
    );
  }

  AccountInfo _account(String uuid) {
    final accounts = _ref.read(accountProvider).value?.accounts ?? const [];
    for (final account in accounts) {
      if (account.uuid == uuid && account.isLedger) return account;
    }
    throw ArgumentError.value(uuid, 'accountUuid', 'Unknown Ledger account');
  }

  List<LedgerConnectionTransport> _candidates(AccountInfo account) {
    final platform = _ref.read(ledgerTargetPlatformProvider);
    if (isLedgerMobilePlatform(platform)) {
      return const [LedgerConnectionTransport.bluetooth];
    }
    if (!ledgerSupportsBluetooth(platform)) {
      return const [LedgerConnectionTransport.usb];
    }
    return switch (account.ledgerConnectionPreference) {
      LedgerConnectionPreference.usb => const [LedgerConnectionTransport.usb],
      LedgerConnectionPreference.bluetooth => const [
        LedgerConnectionTransport.bluetooth,
      ],
      LedgerConnectionPreference.automatic => [
        ?account.ledgerLastTransport,
        if (account.ledgerLastTransport != LedgerConnectionTransport.usb)
          LedgerConnectionTransport.usb,
        if (account.ledgerDeviceId != null &&
            account.ledgerLastTransport != LedgerConnectionTransport.bluetooth)
          LedgerConnectionTransport.bluetooth,
      ],
    };
  }

  Future<T> _runUsb<T>(
    void Function() check,
    Future<T> Function() operation,
  ) async {
    await _ref
        .read(
          ledgerAppReadinessServiceForTransportProvider(
            LedgerConnectionTransport.usb,
          ),
        )
        .ensureReady();
    check();
    return operation();
  }

  Future<T> _runBluetooth<T>(
    void Function() check,
    AccountInfo account,
    Future<T> Function(LedgerMobileBleService mobile) operation,
  ) async {
    await _ref.read(ledgerMobileSigningStatusGateProvider).waitUntilReady();
    check();
    final deviceId = account.ledgerDeviceId;
    if (deviceId == null) {
      throw const LedgerConnectionRequiredException(
        'No Bluetooth device is paired with this Ledger account.',
      );
    }
    final platform = _ref.read(ledgerTargetPlatformProvider);
    if (ledgerBluetoothTransportCapabilityForModel(
          model: account.ledgerDeviceModel,
          platform: platform,
        ) ==
        LedgerBluetoothCapability.unsupported) {
      throw LedgerConnectionRequiredException(
        '${account.ledgerDeviceModel ?? 'This Ledger model'} does not support Bluetooth.',
      );
    }

    final mobile = _ref.read(ledgerMobileBleServiceProvider);
    final device = LedgerBleDevice(
      id: deviceId,
      name: account.ledgerDeviceName ?? 'Ledger',
      model: account.ledgerDeviceModel ?? 'Ledger',
    );
    Future<void> reconnect() async {
      // Keep this set until cleanup AND connect have both completed. A null
      // Dart identity may still have a connected/dirty native transport.
      _requiresReconnect = true;
      await mobile.disconnect();
      check();
      await mobile.connect(device);
      check();
      _requiresReconnect = false;
    }

    final readiness = _ref.read(
      ledgerAppReadinessServiceForTransportProvider(
        LedgerConnectionTransport.bluetooth,
      ),
    );
    var reconnected = false;
    try {
      if (platform == TargetPlatform.macOS ||
          _requiresReconnect ||
          mobile.connectedDeviceId != device.id) {
        reconnected = true;
        await reconnect();
      } else {
        await mobile.currentApp();
        check();
      }
      await readiness.ensureReady();
      check();
    } catch (error) {
      check();
      final disconnected =
          error is LedgerMobileException &&
              error.failure == LedgerMobileFailure.disconnected ||
          error is LedgerAppReadinessException && error.canReconnect;
      // Only a failed existing connection gets one automatic preparation retry.
      // Never retry a pairing problem or any operation that reached the signer.
      if (!disconnected || ledgerPairingNeedsReset(error) || reconnected) {
        rethrow;
      }
      await reconnect();
      await readiness.ensureReady();
      check();
    }
    return operation(mobile);
  }

  Future<void> _recordSuccess(
    AccountInfo account,
    LedgerConnectionTransport transport,
  ) async {
    if (account.ledgerLastTransport == transport) return;
    await _ref
        .read(accountProvider.notifier)
        .recordLedgerConnection(uuid: account.uuid, transport: transport);
  }

  static bool _isConnectionFailure(Object error) {
    if (error is LedgerConnectionRequiredException) return true;
    if (error is LedgerAppReadinessException) {
      return error.failure == LedgerAppReadinessFailure.disconnected ||
          error.failure == LedgerAppReadinessFailure.unavailable;
    }
    if (error is LedgerMobileException) {
      return switch (error.failure) {
        LedgerMobileFailure.disconnected ||
        LedgerMobileFailure.bluetoothOff ||
        LedgerMobileFailure.permissionDenied ||
        LedgerMobileFailure.pairingRejected ||
        LedgerMobileFailure.pairingInvalid ||
        LedgerMobileFailure.unavailable => true,
        LedgerMobileFailure.busy ||
        LedgerMobileFailure.locked ||
        LedgerMobileFailure.rejected ||
        LedgerMobileFailure.wrongApp ||
        LedgerMobileFailure.cancelled => false,
      };
    }
    final lower = error.toString().toLowerCase();
    return lower.contains('no ledger') ||
        lower.contains('no device') ||
        lower.contains('not found') ||
        lower.contains('disconnected') ||
        lower.contains('hid') ||
        lower.contains('bluetooth');
  }

  String _connectionFailureMessage(AccountInfo account, Object? error) {
    if (!ledgerSupportsBluetooth(_ref.read(ledgerTargetPlatformProvider))) {
      final suffix = error == null ? '' : ' ${error.toString()}';
      return 'Connect and unlock your Ledger with USB, then try again.$suffix';
    }
    if (ledgerPairingNeedsReset(error)) return kLedgerPairingInvalidMessage;
    final suffix = error == null ? '' : ' ${error.toString()}';
    return switch (account.ledgerConnectionPreference) {
      LedgerConnectionPreference.usb =>
        'Connect and unlock your Ledger with USB, then try again.$suffix',
      LedgerConnectionPreference.bluetooth =>
        'Turn on and unlock your Ledger, then reconnect with Bluetooth.$suffix',
      LedgerConnectionPreference.automatic =>
        'Vizor could not find this Ledger over USB or Bluetooth. Reconnect your Ledger, then try again.$suffix',
    };
  }
}
