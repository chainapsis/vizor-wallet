import 'dart:developer' show log;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;

import 'ledger_bluetooth_access.dart';
import 'ledger_device_selection.dart';
import 'ledger_pairing_recovery_service.dart';
import '../../../providers/account_provider.dart';
import '../ledger_capability.dart';
import '../ledger_error_codes.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_device_request.dart';
import 'ledger_mobile_ble_service.dart';
import 'ledger_signing_status_gate.dart';

class LedgerConnectionRequiredException implements Exception {
  const LedgerConnectionRequiredException(this.message, {this.cause});

  final String message;

  /// The last connection error, kept so callers can classify it.
  final Object? cause;

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
  int _connectionGeneration = 0;

  /// Share exclusion with signing while re-establishing a device identity.
  Future<T> recover<T>(Future<T> Function() action) async {
    if (_running) {
      throw const LedgerMobileException(
        LedgerMobileFailure.busy,
        'Another Ledger operation is still active.',
      );
    }
    _running = true;
    _connectionGeneration++;
    try {
      return await action();
    } finally {
      _running = false;
    }
  }

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
    final scope = LedgerConnectionScope.current ?? LedgerConnectionScope();
    final session = _ref.read(ledgerPairingRecoverySessionProvider)();
    final requestCheck = check;
    void checkContext() {
      requestCheck();
      session();
    }

    final cached = scope.selected;
    if (cached != null) {
      try {
        cached.check();
        checkContext();
        if (cached.accountUuid != accountUuid) {
          throw StateError('Ledger account changed.');
        }
        if (cached.device == null) {
          final result = await _runUsb(checkContext, usb);
          checkContext();
          return result;
        }
        final mobile = _ref.read(ledgerMobileBleServiceProvider);
        if (mobile.connectedDeviceId != cached.device!.id) {
          throw const LedgerMobileException(
            LedgerMobileFailure.disconnected,
            'Select your Ledger again.',
          );
        }
        await _ref
            .read(
              ledgerAppReadinessServiceForTransportProvider(
                LedgerConnectionTransport.bluetooth,
              ),
            )
            .ensureReady();
        checkContext();
        final result = await bluetooth(mobile);
        checkContext();
        return result;
      } catch (_) {
        scope.selected = null;
        rethrow;
      }
    }
    _connectionGeneration++;
    final platform = _ref.read(ledgerTargetPlatformProvider);
    final selectable = ledgerSupportsBluetooth(platform);
    var operationStarted = false;
    Future<T> runUsb() {
      operationStarted = true;
      return usb();
    }

    try {
      final result = selectable
          ? await _runSelection(checkContext, account, scope, runUsb, (mobile) {
              operationStarted = true;
              return bluetooth(mobile);
            })
          : await _runUsb(checkContext, runUsb);
      checkContext();
      try {
        await _recordSuccess(
          account,
          scope.selected?.device != null
              ? LedgerConnectionTransport.bluetooth
              : LedgerConnectionTransport.usb,
        );
      } catch (error, stackTrace) {
        log(
          'Failed to persist the successful Ledger transport.',
          name: 'LedgerConnectionService',
          error: error,
          stackTrace: stackTrace,
        );
      }
      checkContext();
      return result;
    } catch (error) {
      scope.selected = null;
      checkContext();
      // No automatic transport fallback, and never replay an operation.
      if (operationStarted || !_isConnectionFailure(error)) rethrow;
      throw LedgerConnectionRequiredException(
        scope.transport == LedgerConnectionTransport.bluetooth ||
                isLedgerMobilePlatform(platform)
            ? 'Turn on and unlock your Ledger, then reconnect with Bluetooth.'
            : 'Connect and unlock your Ledger with USB, then try again.',
        cause: error,
      );
    }
  }

  AccountInfo _account(String uuid) {
    final accounts = _ref.read(accountProvider).value?.accounts ?? const [];
    for (final account in accounts) {
      if (account.uuid == uuid && account.isLedger) return account;
    }
    throw ArgumentError.value(uuid, 'accountUuid', 'Unknown Ledger account');
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

  Future<T> _runSelection<T>(
    void Function() check,
    AccountInfo account,
    LedgerConnectionScope scope,
    Future<T> Function() usb,
    Future<T> Function(LedgerMobileBleService mobile) operation,
  ) async {
    final canChoose =
        _ref.read(ledgerTargetPlatformProvider) == TargetPlatform.macOS;
    if (!canChoose) {
      await _ref.read(ledgerMobileSigningStatusGateProvider).waitUntilReady();
    }
    check();
    final session = _ref.read(ledgerPairingRecoverySessionProvider)();
    final generation = _connectionGeneration;
    void guard() {
      check();
      session();
      if (generation != _connectionGeneration) {
        throw const LedgerMobileException(
          LedgerMobileFailure.disconnected,
          'Select your Ledger again.',
        );
      }
    }

    final mobile = _ref.read(ledgerMobileBleServiceProvider);
    var bluetoothStarted = false;
    final selected = await _ref
        .read(ledgerDeviceSelectionProvider.notifier)
        .request(
          LedgerDeviceSelectionRequest(
            accountUuid: account.uuid,
            check: guard,
            canChooseTransport: canChoose,
            initialTransport: canChoose
                ? scope.transport
                : LedgerConnectionTransport.bluetooth,
            onTransportChanged: (transport) => scope.transport = transport,
            prepareUsb: () => _runUsb(guard, () async {}),
            stopDiscovery: () async {
              if (bluetoothStarted) await mobile.stopDiscovery();
            },
            cancelDevice: () async {
              if (!bluetoothStarted && canChoose) return;
              try {
                await mobile.cancelSigning();
              } finally {
                await mobile.stopDiscovery();
              }
            },
            prepareDiscovery: () async {
              guard();
              bluetoothStarted = true;
              if (canChoose) {
                await _ref
                    .read(ledgerMobileSigningStatusGateProvider)
                    .waitUntilReady();
              }
              guard();
              await mobile.stopDiscovery();
              guard();
              await mobile.disconnect();
              guard();
              if (!await prepareLedgerBluetoothDiscovery(mobile)) {
                throw const LedgerMobileException(
                  LedgerMobileFailure.permissionDenied,
                  'Allow Bluetooth access to find your Ledger.',
                );
              }
              guard();
            },
            verify: (device, current, saving) {
              bluetoothStarted = true;
              scope.transport = LedgerConnectionTransport.bluetooth;
              return _ref
                  .read(ledgerPairingRecoveryServiceProvider)
                  .verifyAndSaveWithinConnection(
                    accountUuid: account.uuid,
                    device: device,
                    checkCurrent: current,
                    onSaving: saving,
                  );
            },
          ),
        );
    guard();
    scope.selected = selected;
    if (selected.device == null) {
      // Explicit user action; USB retains its existing preparation/signing path.
      // USB readiness was checked while the selection request remained visible.
      return usb();
    }
    if (mobile.connectedDeviceId != selected.device!.id) {
      throw const LedgerMobileException(
        LedgerMobileFailure.disconnected,
        'Select your Ledger again.',
      );
    }
    // Verification already prepared this connection. Do not reconnect here.
    return operation(mobile);
  }

  Future<void> _recordSuccess(
    AccountInfo account,
    LedgerConnectionTransport transport,
  ) async {
    if (_account(account.uuid).ledgerLastTransport == transport) return;
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
        LedgerMobileFailure.locationDisabled ||
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
    return switch (classifyLedgerError(error)) {
      LedgerFailureKind.transportLost ||
      LedgerFailureKind.usbPermission => true,
      _ => false,
    };
  }
}
