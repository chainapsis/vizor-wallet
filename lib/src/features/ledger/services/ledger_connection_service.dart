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

  Future<T> run<T>({
    required String accountUuid,
    required Future<T> Function() usb,
    required Future<T> Function(LedgerMobileBleService mobile) bluetooth,
  }) async {
    final account = _account(accountUuid);
    final candidates = _candidates(account);
    Object? lastConnectionError;

    for (final transport in candidates) {
      try {
        final result = switch (transport) {
          LedgerConnectionTransport.usb => await _runUsb(usb),
          LedgerConnectionTransport.bluetooth => await _runBluetooth(
            account,
            bluetooth,
          ),
        };
        await _recordSuccess(account, transport);
        return result;
      } catch (error) {
        if (!_isConnectionFailure(error)) rethrow;
        lastConnectionError = error;
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
    Future<T> Function(LedgerMobileBleService mobile) operation,
  ) async {
    final deviceId = account.ledgerDeviceId;
    if (deviceId == null) {
      throw const LedgerConnectionRequiredException(
        'Set up Bluetooth for this Ledger account in Account details first.',
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
    if (platform == TargetPlatform.macOS) {
      await mobile.disconnect();
      await mobile.connect(device);
    } else {
      try {
        await mobile.currentApp();
      } on LedgerMobileException catch (error) {
        if (error.failure != LedgerMobileFailure.disconnected) rethrow;
        await mobile.connect(device);
      }
    }
    await _ref
        .read(
          ledgerAppReadinessServiceForTransportProvider(
            LedgerConnectionTransport.bluetooth,
          ),
        )
        .ensureReady();
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
    if (error is LedgerMobileException) {
      return switch (error.failure) {
        LedgerMobileFailure.disconnected ||
        LedgerMobileFailure.bluetoothOff ||
        LedgerMobileFailure.permissionDenied ||
        LedgerMobileFailure.pairingRejected ||
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

  static String _connectionFailureMessage(AccountInfo account, Object? error) {
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
