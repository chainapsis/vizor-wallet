import 'dart:developer' show log;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../ledger_capability.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_mobile_ble_service.dart';

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

  /// Connects the Ledger selected during Bluetooth account onboarding and
  /// verifies that its Zcash app is ready before any account data is read.
  Future<String> connectBluetoothDevice(LedgerBleDevice device) async {
    final platform = _ref.read(ledgerTargetPlatformProvider);
    _requireBluetoothSupport(device.model, platform);
    final mobile = _ref.read(ledgerMobileBleServiceProvider);
    await _requireBluetoothPermission(mobile, platform);
    await _connectSelectedDevice(mobile, device, platform: platform);
    return _ensureBluetoothReady();
  }

  Future<void> reconnect(String accountUuid) => run<void>(
    accountUuid: accountUuid,
    refreshBluetooth: true,
    usb: () async {},
    bluetooth: (_) async {},
  );

  Future<T> run<T>({
    required String accountUuid,
    required Future<T> Function() usb,
    required Future<T> Function(LedgerMobileBleService mobile) bluetooth,
    bool refreshBluetooth = false,
  }) async {
    final account = _account(accountUuid);
    final candidates = _candidates(account);
    Object? lastConnectionError;

    for (final transport in candidates) {
      var operationStarted = false;
      try {
        final result = switch (transport) {
          LedgerConnectionTransport.usb => await _runUsb(() {
            operationStarted = true;
            return usb();
          }),
          LedgerConnectionTransport.bluetooth => await _runBluetooth(account, (
            mobile,
          ) {
            operationStarted = true;
            return bluetooth(mobile);
          }, refresh: refreshBluetooth),
        };
        try {
          await _recordSuccess(account, transport);
        } catch (error, stackTrace) {
          // The caller's operation may already have signed or broadcast. A
          // preference write must never turn that success into a retryable
          // failure or replay the operation over another transport.
          log(
            'Failed to persist the successful Ledger transport.',
            name: 'LedgerConnectionService',
            error: error,
            stackTrace: stackTrace,
          );
        }
        return result;
      } catch (error) {
        // Once the caller's operation has begun, another transport must not
        // replay it. Recovery and a new signing attempt require user action.
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

  Future<T> _runUsb<T>(Future<T> Function() operation) async {
    await _ref
        .read(
          ledgerAppReadinessServiceForTransportProvider(
            LedgerConnectionTransport.usb,
          ),
        )
        .ensureReady();
    return operation();
  }

  Future<T> _runBluetooth<T>(
    AccountInfo account,
    Future<T> Function(LedgerMobileBleService mobile) operation, {
    bool refresh = false,
  }) async {
    final deviceId = account.ledgerDeviceId;
    if (deviceId == null) {
      throw const LedgerConnectionRequiredException(
        'Connect your Ledger with Bluetooth, then try again.',
      );
    }
    final platform = _ref.read(ledgerTargetPlatformProvider);
    _requireBluetoothSupport(account.ledgerDeviceModel, platform);

    final mobile = _ref.read(ledgerMobileBleServiceProvider);
    await _requireBluetoothPermission(mobile, platform);
    final device = LedgerBleDevice(
      id: deviceId,
      name: account.ledgerDeviceName ?? 'Ledger',
      model: account.ledgerDeviceModel ?? 'Ledger',
    );
    if (refresh) {
      await mobile.cancelSigning();
      await mobile.disconnect();
      await _discoverAndConnect(mobile, deviceId);
    } else if (platform == TargetPlatform.macOS) {
      await mobile.disconnect();
      await mobile.connect(device);
    } else if (mobile.connectedDeviceId != device.id) {
      final hadLiveSession = mobile.connectedDeviceId != null;
      if (mobile.connectedDeviceId != null) {
        await mobile.disconnect();
      }
      if (platform == TargetPlatform.android && !hadLiveSession) {
        await _discoverAndConnect(mobile, deviceId);
      } else {
        await mobile.connect(device);
      }
    } else {
      try {
        await mobile.currentApp();
      } on LedgerMobileException catch (error) {
        if (error.failure != LedgerMobileFailure.disconnected) rethrow;
        await mobile.connect(device);
      }
    }
    await _ensureBluetoothReady();
    return operation(mobile);
  }

  void _requireBluetoothSupport(String? model, TargetPlatform platform) {
    if (ledgerBluetoothTransportCapabilityForModel(
          model: model,
          platform: platform,
        ) ==
        LedgerBluetoothCapability.unsupported) {
      throw LedgerConnectionRequiredException(
        '${model ?? 'This Ledger model'} does not support Bluetooth.',
      );
    }
  }

  Future<void> _requireBluetoothPermission(
    LedgerMobileBleService mobile,
    TargetPlatform platform,
  ) async {
    if (!isLedgerMobilePlatform(platform)) return;
    // Onboarding may have asked earlier, but permission can be revoked before
    // a later reconnect.
    if (!await mobile.requestPermissions()) {
      throw const LedgerConnectionRequiredException(
        'Allow Bluetooth for Vizor in Settings, then try again.',
      );
    }
  }

  Future<void> _connectSelectedDevice(
    LedgerMobileBleService mobile,
    LedgerBleDevice device, {
    required TargetPlatform platform,
  }) async {
    if (platform == TargetPlatform.macOS) {
      await mobile.disconnect();
      await mobile.connect(device);
      return;
    }
    if (mobile.connectedDeviceId == device.id) {
      try {
        await mobile.currentApp();
        return;
      } on LedgerMobileException catch (error) {
        if (error.failure != LedgerMobileFailure.disconnected) rethrow;
      }
    } else if (mobile.connectedDeviceId != null) {
      await mobile.disconnect();
    }
    await mobile.connect(device);
  }

  Future<void> _discoverAndConnect(
    LedgerMobileBleService mobile,
    String deviceId,
  ) async {
    try {
      final device = await mobile
          .discoverDevices()
          .asyncExpand<LedgerBleDevice>((update) {
            if (update is LedgerDiscoveryFailed) throw update.error;
            return Stream.fromIterable(
              update is LedgerDevicesDiscovered
                  ? update.devices
                  : <LedgerBleDevice>[],
            );
          })
          .where((candidate) => candidate.id == deviceId)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: (sink) {
              sink.addError(
                const LedgerConnectionRequiredException(
                  'We could not find your Ledger. Keep it nearby, unlocked, and Bluetooth enabled, then try again.',
                ),
              );
              sink.close();
            },
          )
          .first;
      await mobile.connect(device);
    } finally {
      await mobile.stopDiscovery();
    }
  }

  Future<String> _ensureBluetoothReady() => _ref
      .read(
        ledgerAppReadinessServiceForTransportProvider(
          LedgerConnectionTransport.bluetooth,
        ),
      )
      .ensureReady();

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
    if (ledgerPairingNeedsReset(error)) return kLedgerPairingInvalidMessage;
    final suffix = error == null ? '' : ' ${error.toString()}';
    return switch (account.ledgerConnectionPreference) {
      LedgerConnectionPreference.usb =>
        'Connect and unlock your Ledger with USB, then try again.$suffix',
      LedgerConnectionPreference.bluetooth =>
        'Turn on and unlock your Ledger, then reconnect with Bluetooth.$suffix',
      LedgerConnectionPreference.automatic =>
        'Vizor could not find this Ledger over USB or Bluetooth. Choose a connection in Account details, then try again.$suffix',
    };
  }
}
