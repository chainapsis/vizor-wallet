import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/ledger.dart' as rust_ledger;

enum LedgerMobileFailure {
  permissionDenied,
  bluetoothOff,
  pairingRejected,
  disconnected,
  locked,
  rejected,
  wrongApp,
  cancelled,
  unavailable,
}

class LedgerMobileException implements Exception {
  const LedgerMobileException(this.failure, this.message);

  final LedgerMobileFailure failure;
  final String message;

  @override
  String toString() => message;
}

class LedgerBleDevice {
  const LedgerBleDevice({
    required this.id,
    required this.name,
    required this.model,
  });

  final String id;
  final String name;
  final String model;
}

class LedgerMobileAppInfo {
  const LedgerMobileAppInfo({required this.name, required this.version});

  final String name;
  final String version;
}

sealed class LedgerDiscoveryUpdate {
  const LedgerDiscoveryUpdate();
}

class LedgerDevicesDiscovered extends LedgerDiscoveryUpdate {
  const LedgerDevicesDiscovered(this.devices);

  final List<LedgerBleDevice> devices;
}

class LedgerDiscoveryEnded extends LedgerDiscoveryUpdate {
  const LedgerDiscoveryEnded();
}

class LedgerDiscoveryFailed extends LedgerDiscoveryUpdate {
  const LedgerDiscoveryFailed(this.error);

  final LedgerMobileException error;
}

abstract interface class LedgerMobileBleService {
  String? get connectedDeviceId;

  Stream<LedgerDiscoveryUpdate> discoverDevices();

  Future<bool> requestPermissions();

  Future<void> stopDiscovery();

  Future<void> connect(LedgerBleDevice device);

  Future<void> disconnect();

  Future<LedgerMobileAppInfo> currentApp();

  Future<LedgerMobileAppInfo> requestOpenZcashApp();

  Future<List<Uint8List>> exchangeUfvk(rust_ledger.LedgerUfvkApduPlan plan);

  Future<List<Uint8List>> exchangeApdus(
    List<rust_ledger.LedgerApduCommand> commands,
  );

  Future<void> cancelSigning();
}

final ledgerMobileBleServiceProvider = Provider<LedgerMobileBleService>((_) {
  return MethodChannelLedgerMobileBleService();
});

class MethodChannelLedgerMobileBleService implements LedgerMobileBleService {
  static const _methods = MethodChannel('com.zcash.wallet/ledger_mobile');
  static const _events = EventChannel(
    'com.zcash.wallet/ledger_mobile/discovery',
  );
  String? _connectedDeviceId;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() async* {
    final controller = StreamController<Object?>();
    final subscription = _events.receiveBroadcastStream().listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    try {
      await _methods.invokeMethod<void>('startDiscovery');
      await for (final event in controller.stream) {
        yield _decodeDiscoveryEvent(event);
      }
    } on PlatformException catch (error) {
      yield LedgerDiscoveryFailed(_mapPlatformError(error));
    } finally {
      await subscription.cancel();
      if (!controller.isClosed) await controller.close();
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      return await _methods.invokeMethod<bool>('requestPermissions') ?? false;
    } on PlatformException catch (error) {
      throw _mapPlatformError(error);
    }
  }

  @override
  Future<void> stopDiscovery() => _invokeVoid('stopDiscovery');

  @override
  Future<void> connect(LedgerBleDevice device) async {
    await _invokeVoid('connect', <String, Object>{
      'deviceId': device.id,
      'deviceName': device.name,
      'deviceModel': device.model,
    });
    _connectedDeviceId = device.id;
  }

  @override
  Future<void> disconnect() async {
    await _invokeVoid('disconnect');
    _connectedDeviceId = null;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    try {
      final value = await _invokeMap('currentApp');
      return _decodeApp(value);
    } on LedgerMobileException catch (error) {
      if (error.failure == LedgerMobileFailure.disconnected) {
        _connectedDeviceId = null;
      }
      rethrow;
    }
  }

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() async {
    final value = await _invokeMap('openZcashApp');
    return _decodeApp(value);
  }

  @override
  Future<List<Uint8List>> exchangeUfvk(
    rust_ledger.LedgerUfvkApduPlan plan,
  ) async {
    try {
      final result = await _methods.invokeListMethod<Object>('exchangeUfvk', {
        'first': _encodeCommand(plan.first),
        'continuation': _encodeCommand(plan.continuation),
      });
      return (result ?? const <Object>[])
          .map(
            (chunk) =>
                Uint8List.fromList(List<int>.from(chunk as List<Object?>)),
          )
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw _mapPlatformError(error);
    }
  }

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<rust_ledger.LedgerApduCommand> commands,
  ) async {
    try {
      final result = await _methods.invokeListMethod<Object>('exchangeApdus', {
        'commands': commands.map(_encodeCommand).toList(growable: false),
      });
      return (result ?? const <Object>[])
          .map(
            (response) =>
                Uint8List.fromList(List<int>.from(response as List<Object?>)),
          )
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw _mapPlatformError(error);
    }
  }

  @override
  Future<void> cancelSigning() => _invokeVoid('cancelSigning');

  Future<void> _invokeVoid(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    try {
      await _methods.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw _mapPlatformError(error);
    }
  }

  Future<Map<Object?, Object?>> _invokeMap(String method) async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(method);
      if (result == null) {
        throw const LedgerMobileException(
          LedgerMobileFailure.unavailable,
          'Ledger returned an empty response.',
        );
      }
      return result;
    } on PlatformException catch (error) {
      throw _mapPlatformError(error);
    }
  }

  static Map<String, Object> _encodeCommand(
    rust_ledger.LedgerApduCommand command,
  ) => <String, Object>{
    'cla': command.cla,
    'ins': command.ins,
    'p1': command.p1,
    'p2': command.p2,
    'data': command.data,
  };

  static LedgerMobileAppInfo _decodeApp(Map<Object?, Object?> value) {
    return LedgerMobileAppInfo(
      name: value['name']! as String,
      version: value['version']! as String,
    );
  }

  static LedgerDiscoveryUpdate _decodeDiscoveryEvent(Object? event) {
    final value = event! as Map<Object?, Object?>;
    switch (value['type']) {
      case 'devices':
        final devices = (value['devices']! as List<Object?>)
            .map((item) {
              final device = item! as Map<Object?, Object?>;
              return LedgerBleDevice(
                id: device['id']! as String,
                name: device['name']! as String,
                model: device['model']! as String,
              );
            })
            .toList(growable: false);
        return LedgerDevicesDiscovered(devices);
      case 'ended':
        return const LedgerDiscoveryEnded();
      case 'error':
        return LedgerDiscoveryFailed(
          _errorFromCode(
            value['code'] as String? ?? 'unavailable',
            value['message'] as String? ?? 'Ledger discovery failed.',
          ),
        );
      default:
        return const LedgerDiscoveryFailed(
          LedgerMobileException(
            LedgerMobileFailure.unavailable,
            'Ledger discovery returned an unknown event.',
          ),
        );
    }
  }

  static LedgerMobileException _mapPlatformError(PlatformException error) {
    return _errorFromCode(
      error.code,
      error.message ?? 'Ledger mobile connection failed.',
    );
  }

  static LedgerMobileException _errorFromCode(String code, String message) {
    final failure = switch (code) {
      'permission_denied' => LedgerMobileFailure.permissionDenied,
      'bluetooth_off' => LedgerMobileFailure.bluetoothOff,
      'pairing_rejected' => LedgerMobileFailure.pairingRejected,
      'disconnected' => LedgerMobileFailure.disconnected,
      'locked' => LedgerMobileFailure.locked,
      'rejected' => LedgerMobileFailure.rejected,
      'wrong_app' => LedgerMobileFailure.wrongApp,
      'cancelled' => LedgerMobileFailure.cancelled,
      _ => LedgerMobileFailure.unavailable,
    };
    return LedgerMobileException(failure, message);
  }
}
