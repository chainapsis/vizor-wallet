import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_models.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
import '../ledger_capability.dart';
import 'ledger_mobile_ble_service.dart';

enum LedgerDeviceAppStatus { open, dashboard, locked, disconnected, other }

class LedgerDeviceAppSnapshot {
  const LedgerDeviceAppSnapshot({required this.status, this.version});

  final LedgerDeviceAppStatus status;
  final String? version;
}

abstract interface class LedgerAppReadinessDevice {
  Future<LedgerDeviceAppSnapshot> queryZcashApp();

  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp();
}

enum LedgerAppReadinessPhase {
  idle,
  checkingDevice,
  confirmOpening,
  ready,
  failed,
}

enum LedgerAppReadinessFailure {
  rejected,
  locked,
  disconnected,
  unsupportedVersion,
  unavailable,
}

class LedgerAppReadinessState {
  const LedgerAppReadinessState._({
    required this.phase,
    this.failure,
    this.message,
    this.version,
  });

  const LedgerAppReadinessState.idle()
    : this._(phase: LedgerAppReadinessPhase.idle);

  const LedgerAppReadinessState.inProgress(this.phase)
    : assert(
        phase != LedgerAppReadinessPhase.idle &&
            phase != LedgerAppReadinessPhase.ready &&
            phase != LedgerAppReadinessPhase.failed,
      ),
      failure = null,
      message = null,
      version = null;

  const LedgerAppReadinessState.ready(String version)
    : this._(phase: LedgerAppReadinessPhase.ready, version: version);

  const LedgerAppReadinessState.failed({
    required LedgerAppReadinessFailure failure,
    required String message,
  }) : this._(
         phase: LedgerAppReadinessPhase.failed,
         failure: failure,
         message: message,
       );

  final LedgerAppReadinessPhase phase;
  final LedgerAppReadinessFailure? failure;
  final String? message;
  final String? version;
}

class LedgerAppReadinessException implements Exception {
  const LedgerAppReadinessException(this.failure, this.message);

  final LedgerAppReadinessFailure failure;
  final String message;

  @override
  String toString() => message;
}

class LedgerAppReadinessController extends Notifier<LedgerAppReadinessState> {
  @override
  LedgerAppReadinessState build() => const LedgerAppReadinessState.idle();

  void update(LedgerAppReadinessState next) => state = next;
}

final ledgerAppReadinessStateProvider =
    NotifierProvider<LedgerAppReadinessController, LedgerAppReadinessState>(
      LedgerAppReadinessController.new,
    );

final ledgerAppReadinessDeviceForTransportProvider =
    Provider.family<LedgerAppReadinessDevice, LedgerConnectionTransport>(
      (ref, transport) => switch (transport) {
        LedgerConnectionTransport.usb => const _RustLedgerAppReadinessDevice(),
        LedgerConnectionTransport.bluetooth => _MobileLedgerAppReadinessDevice(
          ref.watch(ledgerMobileBleServiceProvider),
        ),
      },
    );

final ledgerAppReadinessDeviceProvider = Provider<LedgerAppReadinessDevice>((
  ref,
) {
  final transport =
      isLedgerMobilePlatform(ref.watch(ledgerTargetPlatformProvider))
      ? LedgerConnectionTransport.bluetooth
      : LedgerConnectionTransport.usb;
  return ref.watch(ledgerAppReadinessDeviceForTransportProvider(transport));
});

final ledgerAppReadinessServiceProvider = Provider<LedgerAppReadinessService>((
  ref,
) {
  return LedgerAppReadinessService(
    device: ref.watch(ledgerAppReadinessDeviceProvider),
    onState: ref.read(ledgerAppReadinessStateProvider.notifier).update,
  );
});

final ledgerAppReadinessServiceForTransportProvider =
    Provider.family<LedgerAppReadinessService, LedgerConnectionTransport>(
      (ref, transport) => LedgerAppReadinessService(
        device: ref.watch(
          ledgerAppReadinessDeviceForTransportProvider(transport),
        ),
        onState: ref.read(ledgerAppReadinessStateProvider.notifier).update,
      ),
    );

class LedgerAppReadinessService {
  const LedgerAppReadinessService({
    required LedgerAppReadinessDevice device,
    required void Function(LedgerAppReadinessState state) onState,
  }) : _device = device,
       _onState = onState;

  final LedgerAppReadinessDevice _device;
  final void Function(LedgerAppReadinessState state) _onState;

  Future<String> ensureReady() async {
    _onState(
      const LedgerAppReadinessState.inProgress(
        LedgerAppReadinessPhase.checkingDevice,
      ),
    );

    try {
      var snapshot = await _device.queryZcashApp();
      if (snapshot.status == LedgerDeviceAppStatus.dashboard ||
          snapshot.status == LedgerDeviceAppStatus.other) {
        _onState(
          const LedgerAppReadinessState.inProgress(
            LedgerAppReadinessPhase.confirmOpening,
          ),
        );
        snapshot = await _device.requestOpenZcashApp();
      }

      final version = _requireOpenAndSupported(snapshot);
      _onState(LedgerAppReadinessState.ready(version));
      return version;
    } catch (error) {
      final failure = _classifyError(error);
      _onState(
        LedgerAppReadinessState.failed(
          failure: failure.failure,
          message: failure.message,
        ),
      );
      throw failure;
    }
  }

  String _requireOpenAndSupported(LedgerDeviceAppSnapshot snapshot) {
    switch (snapshot.status) {
      case LedgerDeviceAppStatus.open:
        final version = snapshot.version;
        if (version == null) {
          throw const LedgerAppReadinessException(
            LedgerAppReadinessFailure.unavailable,
            'Vizor could not verify the Ledger Zcash app. Try again.',
          );
        }
        try {
          requireSupportedLedgerAppVersion(version);
        } on UnsupportedError {
          throw const LedgerAppReadinessException(
            LedgerAppReadinessFailure.unsupportedVersion,
            'Update the Ledger Zcash app to version '
            '$kMinimumLedgerZcashAppVersion or newer.',
          );
        }
        return version;
      case LedgerDeviceAppStatus.dashboard:
      case LedgerDeviceAppStatus.other:
        throw const LedgerAppReadinessException(
          LedgerAppReadinessFailure.unavailable,
          'Open the Zcash app on your Ledger, then try again.',
        );
      case LedgerDeviceAppStatus.locked:
        throw const LedgerAppReadinessException(
          LedgerAppReadinessFailure.locked,
          'Unlock your Ledger, then try again.',
        );
      case LedgerDeviceAppStatus.disconnected:
        throw const LedgerAppReadinessException(
          LedgerAppReadinessFailure.disconnected,
          'Reconnect and unlock your Ledger, then try again.',
        );
    }
  }

  LedgerAppReadinessException _classifyError(Object error) {
    if (error is LedgerAppReadinessException) return error;
    if (error is LedgerMobileException) {
      final failure = switch (error.failure) {
        LedgerMobileFailure.pairingRejected ||
        LedgerMobileFailure.disconnected =>
          LedgerAppReadinessFailure.disconnected,
        LedgerMobileFailure.locked => LedgerAppReadinessFailure.locked,
        LedgerMobileFailure.rejected ||
        LedgerMobileFailure.cancelled => LedgerAppReadinessFailure.rejected,
        LedgerMobileFailure.permissionDenied ||
        LedgerMobileFailure.bluetoothOff ||
        LedgerMobileFailure.wrongApp ||
        LedgerMobileFailure.unavailable =>
          LedgerAppReadinessFailure.unavailable,
      };
      return LedgerAppReadinessException(failure, error.message);
    }
    final raw = '$error'.toLowerCase();
    if (raw.contains('rejected') ||
        raw.contains('denied') ||
        raw.contains('6985')) {
      return const LedgerAppReadinessException(
        LedgerAppReadinessFailure.rejected,
        'The request was rejected on your Ledger. Try again when ready.',
      );
    }
    if (raw.contains('locked') || raw.contains('5515')) {
      return const LedgerAppReadinessException(
        LedgerAppReadinessFailure.locked,
        'Unlock your Ledger, then try again.',
      );
    }
    if (raw.contains('disconnect') ||
        raw.contains('not found') ||
        raw.contains('no device') ||
        raw.contains('hid')) {
      return const LedgerAppReadinessException(
        LedgerAppReadinessFailure.disconnected,
        'Reconnect and unlock your Ledger, then try again.',
      );
    }
    return const LedgerAppReadinessException(
      LedgerAppReadinessFailure.unavailable,
      'Vizor could not prepare the Ledger Zcash app. Try again.',
    );
  }
}

class _RustLedgerAppReadinessDevice implements LedgerAppReadinessDevice {
  const _RustLedgerAppReadinessDevice();

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async {
    final app = await rust_ledger.ledgerDeviceApp();
    return _snapshotFromRust(app);
  }

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() async {
    final app = await rust_ledger.ledgerOpenZcashApp();
    return _snapshotFromRust(app);
  }

  LedgerDeviceAppSnapshot _snapshotFromRust(rust_ledger.LedgerDeviceApp app) {
    final status = switch (app.appName) {
      'Zcash' => LedgerDeviceAppStatus.open,
      'BOLOS' || 'OLOS' || 'OLOS\u0000' => LedgerDeviceAppStatus.dashboard,
      _ => LedgerDeviceAppStatus.other,
    };
    return LedgerDeviceAppSnapshot(status: status, version: app.appVersion);
  }
}

class _MobileLedgerAppReadinessDevice implements LedgerAppReadinessDevice {
  const _MobileLedgerAppReadinessDevice(this._mobile);

  final LedgerMobileBleService _mobile;

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async {
    return _snapshot(await _mobile.currentApp());
  }

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() async {
    return _snapshot(await _mobile.requestOpenZcashApp());
  }

  LedgerDeviceAppSnapshot _snapshot(LedgerMobileAppInfo app) {
    final status = switch (app.name) {
      'Zcash' => LedgerDeviceAppStatus.open,
      'BOLOS' || 'OLOS' || 'OLOS\u0000' => LedgerDeviceAppStatus.dashboard,
      _ => LedgerDeviceAppStatus.other,
    };
    return LedgerDeviceAppSnapshot(status: status, version: app.version);
  }
}
