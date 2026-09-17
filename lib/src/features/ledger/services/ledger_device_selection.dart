import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import 'ledger_device_request.dart';
import 'ledger_mobile_ble_service.dart';

/// One user operation, including all of its signing rounds. Never persisted.
class LedgerConnectionScope {
  static final _zoneKey = Object();
  static LedgerConnectionScope? get current =>
      Zone.current[_zoneKey] as LedgerConnectionScope?;
  LedgerSelectedConnection? selected;
  // This user's current operation only; never copied into account metadata.
  LedgerConnectionTransport? transport;

  void changeConnection() {
    selected = null;
    transport = null;
  }

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});
}

class LedgerSelectedConnection {
  LedgerSelectedConnection(this.accountUuid, this.device, this.check);
  final String accountUuid;
  // Null means the user explicitly chose USB.
  final LedgerBleDevice? device;
  final void Function() check;
}

typedef LedgerSelectionVerifier =
    Future<bool> Function(
      LedgerBleDevice device,
      void Function() check,
      void Function() onSaving,
    );

enum LedgerDeviceSelectionOutcome { selected, saved }

/// The connection service owns exclusion while this request is visible. UI may
/// scan and verify through this request, but cannot start a second operation.
class LedgerDeviceSelectionRequest {
  LedgerDeviceSelectionRequest({
    required this.accountUuid,
    required this.check,
    required this.prepareDiscovery,
    required this.verify,
    this.cancelDevice,
    this.canChooseTransport = false,
    this.initialTransport,
    this.prepareUsb,
    this.stopDiscovery,
    this.onTransportChanged,
  });
  final String accountUuid;
  final void Function() check;
  final Future<void> Function() prepareDiscovery;
  final LedgerSelectionVerifier verify;
  final Future<void> Function()? cancelDevice;
  final bool canChooseTransport;
  final LedgerConnectionTransport? initialTransport;
  final Future<void> Function()? prepareUsb;
  final Future<void> Function()? stopDiscovery;
  final void Function(LedgerConnectionTransport?)? onTransportChanged;

  void chooseTransport(LedgerConnectionTransport? transport) {
    requireCurrent();
    if (_work != null) throw StateError('Ledger selection is busy.');
    onTransportChanged?.call(transport);
  }

  // A completed stop belongs to this picker, so disposal must not send a
  // second global native stop that could race the next connection attempt.
  bool _discoveryStopped = false;
  bool get discoveryStopped => _discoveryStopped;
  Future<void> stop() => _prepare(() async {
    await stopDiscovery?.call();
    _discoveryStopped = true;
  });
  Future<void>? _cancelWork;
  final _result = Completer<LedgerSelectedConnection>();
  Future<void>? _work;
  bool get completed => _result.isCompleted;
  bool get busy => _work != null;

  void requireCurrent() {
    check();
    if (completed) {
      throw const LedgerMobileException(
        LedgerMobileFailure.cancelled,
        'Cancelled',
      );
    }
  }

  Future<void> prepare() => _prepare(() {
    _discoveryStopped = false;
    return prepareDiscovery();
  });

  Future<void> _prepare(Future<void> Function() action) async {
    requireCurrent();
    if (_work != null) throw StateError('Ledger selection is busy.');
    final work = action();
    final drained = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    _work = drained;
    try {
      await work;
      requireCurrent();
    } finally {
      if (identical(_work, drained)) _work = null;
    }
  }

  Future<LedgerDeviceSelectionOutcome> select(
    LedgerBleDevice device,
    void Function() current,
    void Function() onSaving,
  ) async {
    requireCurrent();
    if (_work != null) {
      throw const LedgerMobileException(
        LedgerMobileFailure.busy,
        'Another Ledger operation is still active.',
      );
    }
    void guard() {
      requireCurrent();
      current();
    }

    var savedConnection = false;
    final work = verify(device, guard, () {
      savedConnection = true;
      onSaving();
    });
    final drained = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    _work = drained;
    try {
      await work;
      guard();
      // Viewing-key approval ends this connection attempt. Keep the owning
      // operation pending until the user finds and selects a device again.
      // Use the save boundary, including accounts without a previous device ID.
      if (savedConnection) return LedgerDeviceSelectionOutcome.saved;
      _result.complete(LedgerSelectedConnection(accountUuid, device, check));
      return LedgerDeviceSelectionOutcome.selected;
    } finally {
      if (identical(_work, drained)) _work = null;
    }
  }

  Future<void> selectUsb() async {
    chooseTransport(LedgerConnectionTransport.usb);
    await _prepare(prepareUsb ?? () async {});
    requireCurrent();
    _result.complete(LedgerSelectedConnection(accountUuid, null, check));
  }

  void cancel() {
    if (!completed) {
      _cancelWork = () async {
        try {
          await cancelDevice?.call();
        } catch (_) {}
      }();
      _result.completeError(
        const LedgerMobileException(
          LedgerMobileFailure.cancelled,
          'Ledger operation was cancelled.',
        ),
      );
    }
  }

  Future<LedgerSelectedConnection> get result async {
    try {
      return await _result.future;
    } finally {
      await _cancelWork;
      await _work;
    }
  }
}

final ledgerDeviceSelectionProvider =
    NotifierProvider<
      LedgerDeviceSelectionController,
      LedgerDeviceSelectionRequest?
    >(LedgerDeviceSelectionController.new);

class LedgerDeviceSelectionController
    extends Notifier<LedgerDeviceSelectionRequest?> {
  LedgerDeviceSelectionRequest? _pending;

  @override
  LedgerDeviceSelectionRequest? build() {
    final requests = ref.read(ledgerDeviceRequestsProvider);
    void cancel() => _pending?.cancel();
    requests.addCancellationListener(cancel);
    ref.listen(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (_, _) => cancel(),
    );
    ref.listen(appSecurityProvider, (_, _) => cancel());
    ref.onDispose(() {
      requests.removeCancellationListener(cancel);
      cancel();
    });
    return null;
  }

  Future<LedgerSelectedConnection> request(
    LedgerDeviceSelectionRequest request,
  ) async {
    if (state != null) {
      throw const LedgerMobileException(
        LedgerMobileFailure.busy,
        'Another Ledger operation is still active.',
      );
    }
    _pending = request;
    state = request;
    try {
      return await request.result;
    } finally {
      if (identical(_pending, request)) _pending = null;
      if (ref.mounted && identical(state, request)) state = null;
    }
  }
}
