import 'dart:developer' show log;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ledger_bluetooth_access.dart';
import 'ledger_device_selection.dart';
import 'ledger_pairing_recovery_service.dart';
import '../../../providers/account_provider.dart';
import '../ledger_capability.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_device_request.dart';
import 'ledger_mobile_ble_service.dart';
import 'ledger_signing_status_gate.dart';

class LedgerConnectionRequiredException implements Exception {
  const LedgerConnectionRequiredException(this.message, {this.cause});

  final Object? cause;

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
    final candidates = _candidates(account);
    Object? lastConnectionError;

    for (final transport in candidates) {
      check();
      var operationStarted = false;
      try {
        final result = switch (transport) {
          LedgerConnectionTransport.usb => await _runUsb(check, () {
            operationStarted = true;
            return usb();
          }),
          LedgerConnectionTransport.bluetooth => await _runBluetooth(
            check,
            account,
            scope,
            () {
              operationStarted = true;
              return usb();
            },
            (mobile) {
              operationStarted = true;
              return bluetooth(mobile);
            },
          ),
        };
        check();
        try {
          await _recordSuccess(
            account,
            scope.selected != null && scope.selected!.device == null
                ? LedgerConnectionTransport.usb
                : transport,
          );
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
        scope.selected = null;
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
      cause: lastConnectionError,
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
      LedgerConnectionPreference.automatic => const [
        LedgerConnectionTransport.usb,
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
    LedgerConnectionScope scope,
    Future<T> Function() usb,
    Future<T> Function(LedgerMobileBleService mobile) operation,
  ) async {
    await _ref.read(ledgerMobileSigningStatusGateProvider).waitUntilReady();
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
    final selected = await _ref
        .read(ledgerDeviceSelectionProvider.notifier)
        .request(
          LedgerDeviceSelectionRequest(
            accountUuid: account.uuid,
            check: guard,
            cancelDevice: () async {
              try {
                await mobile.cancelSigning();
              } finally {
                await mobile.stopDiscovery();
              }
            },
            prepareDiscovery: () async {
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
            verify: (device, current, saving) => _ref
                .read(ledgerPairingRecoveryServiceProvider)
                .verifyAndSaveWithinConnection(
                  accountUuid: account.uuid,
                  device: device,
                  checkCurrent: current,
                  onSaving: saving,
                ),
          ),
        );
    guard();
    scope.selected = selected;
    if (selected.device == null) {
      // Explicit user action; USB retains its existing preparation/signing path.
      return _runUsb(guard, usb);
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
    if (isLedgerMobilePlatform(_ref.read(ledgerTargetPlatformProvider))) {
      return 'Turn on and unlock your Ledger, then reconnect with Bluetooth.$suffix';
    }
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
