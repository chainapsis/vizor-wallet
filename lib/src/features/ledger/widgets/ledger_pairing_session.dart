import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../ledger_capability.dart';
import '../services/ledger_bluetooth_access.dart';
import '../services/ledger_connection_service.dart';
import '../services/ledger_device_request.dart';
import '../services/ledger_device_selection.dart';
import '../services/ledger_failure_guidance.dart';
import '../services/ledger_mobile_ble_service.dart';
import '../services/ledger_pairing_recovery_service.dart';
import '../services/ledger_signing_service.dart';

enum LedgerPairingStage {
  failed,
  scanning,
  devices,
  verifying,
  saving,
  saved,
  ready,
  mismatch,
}

class LedgerPairingSession extends ConsumerStatefulWidget {
  const LedgerPairingSession({
    required this.builder,
    required this.accountUuid,
    required this.onRetry,
    required this.onClose,
    required this.onBusyChanged,
    this.onCanChangeConnectionChanged,
    this.enabled = true,
    this.pairingInvalid = false,
    this.selectionRequest,
    this.retrySelectsDevice = false,
    super.key,
  });
  final Widget Function(BuildContext, LedgerPairingSessionState) builder;
  final String accountUuid;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<bool>? onCanChangeConnectionChanged;
  final bool enabled;
  final bool pairingInvalid;
  final LedgerDeviceSelectionRequest? selectionRequest;
  final bool retrySelectsDevice;

  @override
  ConsumerState<LedgerPairingSession> createState() =>
      LedgerPairingSessionState();
}

class LedgerPairingSessionState extends ConsumerState<LedgerPairingSession> {
  LedgerPairingStage _stage = LedgerPairingStage.failed;
  LedgerRequestFailure requestFailure = LedgerRequestFailure.other;
  late bool pairingInvalid = widget.pairingInvalid;
  bool _sameSavedDevice = false;
  LedgerBleDevice? selectedDevice;
  bool _accessRecovery = false;
  bool _invalidated = false;
  bool _settingsBusy = false;
  String? _error;
  List<LedgerBleDevice> _devices = const [];
  StreamSubscription<LedgerDiscoveryUpdate>? _subscription;
  int _generation = 0;
  ValueListenable<bool>? _pairingEvidence;
  late final LedgerMobileBleService _mobile;
  late final LedgerOperationCanceller _cancel;
  late final void Function() _epoch;

  bool get _busy =>
      _stage == LedgerPairingStage.scanning ||
      _stage == LedgerPairingStage.verifying ||
      _stage == LedgerPairingStage.saving ||
      _settingsBusy;

  @override
  void initState() {
    super.initState();
    _mobile = ref.read(ledgerMobileBleServiceProvider);
    _cancel = ref.read(ledgerOperationCancellerProvider);
    try {
      final request = ref.read(ledgerDeviceRequestsProvider).capture();
      final session = ref.read(ledgerPairingRecoverySessionProvider)();
      _epoch = () {
        request();
        session();
      };
    } catch (_) {
      _invalidated = true;
      _epoch = () => throw StateError('Cancelled');
    }
    _observePairingEvidence();
    if (widget.selectionRequest != null) {
      _stage = LedgerPairingStage.scanning;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_scan(initial: true));
      });
    }
  }

  void _observePairingEvidence() {
    _pairingEvidence?.removeListener(_onPairingEvidence);
    _pairingEvidence = null;
    if (ref.read(ledgerTargetPlatformProvider) != TargetPlatform.android ||
        _mobile is! LedgerPairingEvidenceService) {
      return;
    }
    _pairingEvidence =
        (_mobile as LedgerPairingEvidenceService).pairingInvalidEvidence;
    _pairingEvidence?.addListener(_onPairingEvidence);
    // initState/_fail already schedule a build; avoid synchronous setState here.
    if (_stage == LedgerPairingStage.failed &&
        widget.selectionRequest == null &&
        _pairingEvidence?.value == true) {
      pairingInvalid = true;
    }
  }

  void _onPairingEvidence() {
    if (!mounted ||
        _invalidated ||
        _stage != LedgerPairingStage.failed ||
        _accessRecovery ||
        _pairingEvidence?.value != true) {
      return;
    }
    try {
      _epoch();
    } catch (_) {
      return;
    }
    setState(() {
      pairingInvalid = true;
      _error = null;
    });
  }

  void _check(int generation) {
    _epoch();
    if (!mounted || _invalidated || generation != _generation) {
      throw const LedgerMobileException(
        LedgerMobileFailure.cancelled,
        'Cancelled',
      );
    }
  }

  void _notifyBusy() {
    widget.onBusyChanged(_busy);
    widget.onCanChangeConnectionChanged?.call(
      _stage == LedgerPairingStage.scanning ||
          _stage == LedgerPairingStage.devices ||
          _stage == LedgerPairingStage.failed ||
          _stage == LedgerPairingStage.mismatch,
    );
  }

  @override
  void dispose() {
    _generation++;
    _pairingEvidence?.removeListener(_onPairingEvidence);
    unawaited(_subscription?.cancel());
    if ((_stage == LedgerPairingStage.scanning ||
            _stage == LedgerPairingStage.devices) &&
        widget.selectionRequest?.discoveryStopped != true) {
      unawaited(_stopQuietly());
    }
    if (_stage == LedgerPairingStage.verifying &&
        widget.selectionRequest?.completed != true) {
      unawaited(_cancelQuietly());
    }
    super.dispose();
  }

  Future<void> _cancelQuietly() async {
    try {
      await _cancel();
    } catch (_) {}
  }

  Future<void> _stopQuietly() async {
    try {
      await _mobile.stopDiscovery();
    } catch (_) {}
  }

  void _fail(int generation, Object error) {
    if (!mounted || generation != _generation) return;
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    try {
      _epoch();
    } catch (_) {
      _invalidated = true;
    }
    setState(() {
      _stage = error is LedgerAccountMismatchException
          ? LedgerPairingStage.mismatch
          : LedgerPairingStage.failed;
      _devices = const [];
      pairingInvalid = ledgerFailureGuidance(error)?.pairingInvalid == true;
      _accessRecovery = ledgerFailureGuidance(error)?.bluetoothRecovery == true;
      requestFailure = LedgerRequestFailure.fromError(error);
      _error = null;
    });
    _observePairingEvidence();
    _onPairingEvidence();
    _notifyBusy();
  }

  Future<void> _scan({bool initial = false}) async {
    if ((_busy && !initial) || !widget.enabled || _invalidated) return;
    if (widget.retrySelectsDevice) {
      widget.onRetry?.call();
      return;
    }
    final generation = ++_generation;
    _pairingEvidence?.removeListener(_onPairingEvidence);
    _pairingEvidence = null;
    setState(() {
      _stage = LedgerPairingStage.scanning;
      pairingInvalid = false;
      _error = null;
      _devices = const [];
      _accessRecovery = false;
    });
    _notifyBusy();
    try {
      _check(generation);
      unawaited(_subscription?.cancel());
      _subscription = null;
      if (widget.selectionRequest case final request?) {
        request.requireCurrent();
        await request.prepare();
      } else {
        await ref.read(ledgerConnectionServiceProvider).recover(() async {
          await _mobile.stopDiscovery();
          _check(generation);
          await _mobile.disconnect();
          _check(generation);
          if (!await prepareLedgerBluetoothDiscovery(_mobile)) {
            throw const LedgerMobileException(
              LedgerMobileFailure.permissionDenied,
              'Allow Bluetooth access to find your Ledger.',
            );
          }
          _check(generation);
        });
      }
      _check(generation);
      _notifyBusy();
      _subscription = _mobile.discoverDevices().listen(
        (event) {
          try {
            _check(generation);
            switch (event) {
              case LedgerDevicesDiscovered(:final devices):
                setState(() {
                  _devices = devices;
                });
              case LedgerDiscoveryEnded():
                setState(() {
                  _stage = LedgerPairingStage.devices;
                });
                _notifyBusy();
              case LedgerDiscoveryFailed(:final error):
                _fail(generation, error);
            }
          } catch (error) {
            _fail(generation, error);
          }
        },
        onError: (Object error) => _fail(generation, error),
        onDone: () {
          if (mounted &&
              generation == _generation &&
              _stage == LedgerPairingStage.scanning) {
            setState(() => _stage = LedgerPairingStage.devices);
            _notifyBusy();
          }
        },
      );
    } catch (error) {
      _fail(generation, error);
    }
  }

  Future<void> _select(LedgerBleDevice device) async {
    if ((_stage != LedgerPairingStage.scanning &&
            _stage != LedgerPairingStage.devices) ||
        !widget.enabled ||
        _invalidated) {
      return;
    }
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final savedId = ref
        .read(accountProvider)
        .value
        ?.accounts
        .where((a) => a.uuid == widget.accountUuid)
        .firstOrNull
        ?.ledgerDeviceId;
    setState(() {
      selectedDevice = device;
      _sameSavedDevice = ledgerDeviceMatchesSavedConnection(savedId, device.id);
      _stage = LedgerPairingStage.verifying;
      _error = null;
    });
    _notifyBusy();
    try {
      _check(generation);
      if (widget.selectionRequest case final request?) {
        final outcome = await request.select(
          device,
          () => _check(generation),
          () {
            setState(() => _stage = LedgerPairingStage.saving);
            _notifyBusy();
          },
        );
        if (outcome == LedgerDeviceSelectionOutcome.saved) {
          _check(generation);
          setState(() => _stage = LedgerPairingStage.saved);
          _notifyBusy();
        }
        // A previously saved device resumes the owning operation. A newly
        // saved device stays here until the user explicitly starts discovery.
        return;
      }
      await ref
          .read(ledgerPairingRecoveryServiceProvider)
          .verifyAndSave(
            accountUuid: widget.accountUuid,
            device: device,
            checkCurrent: () => _check(generation),
            onSaving: () {
              setState(() => _stage = LedgerPairingStage.saving);
              _notifyBusy();
            },
          );
      _check(generation);
      setState(() {
        _stage = _sameSavedDevice
            ? LedgerPairingStage.ready
            : LedgerPairingStage.saved;
      });
      _notifyBusy();
    } catch (error) {
      _fail(generation, error);
    }
  }

  Future<void> _settings() async {
    if (_busy || !widget.enabled || _invalidated) return;
    final generation = _generation;
    setState(() => _settingsBusy = true);
    _notifyBusy();
    try {
      _check(generation);
      final opened = await (_mobile as LedgerBluetoothPairingSettings)
          .openBluetoothPairingSettings();
      _check(generation);
      if (!opened) {
        setState(
          () => _error =
              'Open Bluetooth settings manually to remove the old pairing.',
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Open Bluetooth settings manually to remove the old pairing.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _settingsBusy = false);
        _notifyBusy();
      }
    }
  }

  LedgerPairingStage get stage => _stage;
  bool get busy => _busy;
  bool get invalidated => _invalidated;
  bool get accessRecovery => _accessRecovery;
  bool get sameSavedDevice => _sameSavedDevice;
  String? get error => _error;
  List<LedgerBleDevice> get devices => _devices;
  LedgerMobileBleService get service => _mobile;
  Future<void> scan() => _scan();
  Future<void> select(LedgerBleDevice device) => _select(device);
  Future<void> settings() => _settings();
  void continueSigning() {
    try {
      _check(_generation);
      widget.onRetry?.call();
    } catch (error) {
      _fail(_generation, error);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}
