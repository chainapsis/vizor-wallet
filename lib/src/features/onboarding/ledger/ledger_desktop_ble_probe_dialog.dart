import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../ledger/ledger_onboarding_policy.dart';
import '../../ledger/ledger_device_label.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_bluetooth_access.dart';
import '../../ledger/services/ledger_bluetooth_connection.dart';
import '../../ledger/services/ledger_device_request.dart';
import '../../../providers/account_models.dart';
import '../../ledger/services/ledger_failure_guidance.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/widgets/ledger_bluetooth_session.dart';
import '../../ledger/widgets/ledger_bluetooth_restricted_help.dart';
import '../../ledger/widgets/ledger_modal_content.dart';
import '../../ledger/widgets/ledger_procedure.dart';

enum _Phase {
  preparing,
  scanning,
  devices,
  connecting,
  reading,
  empty,
  failed,
  cancelling,
}

class LedgerDesktopConnectModal extends ConsumerStatefulWidget {
  const LedgerDesktopConnectModal({
    required this.transport,
    required this.service,
    required this.usbConnector,
    required this.bluetoothConnector,
    required this.cancelOperation,
    required this.accountIndex,
    required this.onConnected,
    required this.onClose,
    super.key,
  });
  final LedgerConnectionTransport transport;
  final LedgerMobileBleService service;
  final LedgerAccountConnector usbConnector;
  final LedgerBluetoothAccountConnector bluetoothConnector;
  final LedgerOperationCanceller cancelOperation;
  final int accountIndex;
  final ValueChanged<LedgerDeviceAccount> onConnected;
  final VoidCallback onClose;
  @override
  ConsumerState<LedgerDesktopConnectModal> createState() =>
      _LedgerDesktopConnectModalState();
}

class _LedgerDesktopConnectModalState
    extends ConsumerState<LedgerDesktopConnectModal> {
  StreamSubscription<LedgerDiscoveryUpdate>? _subscription;
  Future<void>? _work;
  _Phase _phase = _Phase.preparing;
  List<LedgerBleDevice> _devices = const [];
  LedgerBleDevice? _device;
  String? _error;
  int? _declinedStep;
  int? _resumingStep;
  bool _accessRecovery = false,
      _closing = false,
      _stoppingSearch = false,
      _cleanupFailed = false,
      _retryable = true,
      _reselectAfterCleanup = false,
      _requestStarted = false;
  int _generation = 0;
  bool _discovering = false;
  bool get _bluetooth =>
      widget.transport == LedgerConnectionTransport.bluetooth;
  bool get _declined => _declinedStep != null;
  bool get _choosing =>
      _device == null && _bluetooth && !_declined && !_accessRecovery;
  bool _current(int generation) => mounted && generation == _generation;

  @override
  void initState() {
    super.initState();
    // Readiness publishes provider state before its first native await.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_bluetooth) {
        _search();
      } else {
        _read();
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription?.cancel());
    // Native work is drained before closing; never send a late global stop.
    super.dispose();
  }

  Future<void> _stopDiscovery() async {
    final subscription = _subscription;
    _subscription = null;
    await Future.wait<void>([
      subscription?.cancel() ?? Future<void>.value(),
      widget.service.stopDiscovery(),
    ], eagerError: true);
    _discovering = false;
  }

  void _search() {
    if (_closing ||
        (_work != null &&
            (_phase == _Phase.preparing || _phase == _Phase.scanning))) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _phase = _Phase.preparing;
      _devices = const [];
      _device = null;
      _error = null;
      _retryable = true;
      _accessRecovery = false;
      _declinedStep = null;
      _resumingStep = null;
      _cleanupFailed = false;
      _reselectAfterCleanup = false;
      _requestStarted = false;
    });
    _work = _discover(generation);
    unawaited(_work);
  }

  Future<void> _discover(int generation) async {
    try {
      await _stopDiscovery();
      if (!_current(generation)) return;
      await widget.service.disconnect();
      if (!_current(generation)) return;
      final granted = await prepareLedgerBluetoothDiscovery(widget.service);
      if (!_current(generation)) return;
      if (!granted) {
        _fail(
          generation,
          const LedgerMobileException(
            LedgerMobileFailure.permissionDenied,
            'Allow Bluetooth access for Vizor in System Settings.',
          ),
        );
        return;
      }
      setState(() {
        _phase = _Phase.scanning;
        _discovering = true;
      });
      _subscription = widget.service.discoverDevices().listen(
        (update) {
          if (!_current(generation)) return;
          switch (update) {
            case LedgerDevicesDiscovered(:final devices):
              setState(() {
                _devices = devices;
                _phase = devices.isEmpty ? _Phase.scanning : _Phase.devices;
              });
            case LedgerDiscoveryEnded():
              _discovering = false;
              setState(
                () => _phase = _devices.isEmpty ? _Phase.empty : _Phase.devices,
              );
            case LedgerDiscoveryFailed(:final error):
              _fail(generation, error);
          }
        },
        onError: (Object error) => _fail(generation, error),
        onDone: () {
          if (!_current(generation) ||
              ![_Phase.scanning, _Phase.devices].contains(_phase)) {
            return;
          }
          _subscription = null;
          setState(() {
            _discovering = false;
            _phase = _devices.isEmpty ? _Phase.empty : _Phase.devices;
          });
        },
      );
    } catch (error) {
      _fail(generation, error);
    }
  }

  void _read([LedgerBleDevice? device]) {
    if (_closing || _phase == _Phase.connecting || _phase == _Phase.reading) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _requestStarted = true;
      _resumingStep = _declinedStep;
      _declinedStep = null;
      _error = null;
      _accessRecovery = false;
      _device = device ?? _device;
      _phase = _Phase.connecting;
    });
    _work = _readAccount(generation);
    unawaited(_work);
  }

  Future<void> _readAccount(int generation) async {
    try {
      if (_bluetooth) {
        final check = ref.read(ledgerDeviceRequestsProvider).capture();
        void checkCurrent() {
          check();
          if (!_current(generation)) {
            throw const LedgerMobileException(
              LedgerMobileFailure.cancelled,
              'Ledger operation was cancelled.',
            );
          }
        }

        await _stopDiscovery();
        checkCurrent();
        await reconnectLedgerBluetoothDevice(
          service: widget.service,
          device: _device!,
          checkCurrent: checkCurrent,
        );
      }
      setState(() => _phase = _Phase.reading);
      final account = _bluetooth
          ? await widget.bluetoothConnector(widget.accountIndex, _device!)
          : await widget.usbConnector(widget.accountIndex);
      if (_current(generation)) widget.onConnected(account);
    } catch (error) {
      _fail(generation, error);
    }
  }

  void _fail(int generation, Object error) {
    if (!_current(generation)) return;
    final guidance = ledgerFailureGuidance(
      error,
      requestKind: LedgerRequestKind.viewingKey,
    );
    setState(() {
      _phase = _Phase.failed;
      _retryable =
          guidance?.retryable ??
          LedgerRequestFailure.fromError(error).retryable;
      _declinedStep =
          LedgerRequestFailure.fromError(error) == LedgerRequestFailure.declined
          ? error is LedgerAppReadinessException
                ? 1
                : 2
          : null;
      _accessRecovery = guidance?.bluetoothRecovery ?? false;
      _error = _declined
          ? _declinedStep == 1
                ? 'Opening Zcash was declined on Ledger. Try again when you’re ready.'
                : 'Sharing was declined on Ledger. Try again when you’re ready.'
          : guidance?.message ??
                (error is LedgerAppReadinessException
                    ? error.message
                    : _bluetooth
                    ? 'Vizor could not read this Ledger account. Try again.'
                    : ledgerUsbErrorMessage(
                            error,
                            appInstruction:
                                'Open the Zcash app, then try again.',
                          ) ??
                          'Vizor could not read this Ledger account. Reconnect Ledger with a USB cable, unlock it with your PIN, and open the Zcash app. Then try again.');
    });
  }

  Future<void> _finish({bool reselect = false}) async {
    if (_closing) return;
    _reselectAfterCleanup = reselect;
    final searching = !_requestStarted;
    _generation++;
    setState(() {
      _closing = true;
      _cleanupFailed = false;
      _stoppingSearch = searching;
      _phase = _Phase.cancelling;
    });
    try {
      if (!searching) await widget.cancelOperation();
      await _work;
      if (_bluetooth) {
        await _stopDiscovery();
        await widget.service.disconnect();
      }
      if (!mounted) return;
      if (reselect && _bluetooth) {
        _closing = false;
        _search();
      } else {
        widget.onClose();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _cleanupFailed = true;
        _accessRecovery = false;
        _phase = _Phase.failed;
        _error = 'Could not finish cleanup. Try again.';
      });
    }
  }

  Widget _footer({String? label, VoidCallback? action}) => label == null
      ? Center(
          child: AppButton(
            size: AppButtonSize.mediumLarge,
            variant: AppButtonVariant.ghost,
            minWidth: kAppModalButtonMinWidth,
            onPressed: () => unawaited(_finish()),
            child: const Text('Cancel'),
          ),
        )
      : AppModalActions(
          onCancel: () => unawaited(_finish()),
          actionLabel: label,
          onAction: action,
        );

  Widget _message(String text) => Text(
    text,
    style: AppTypography.bodyMedium.copyWith(
      color: context.colors.text.secondary,
    ),
  );

  Widget _pending(String text) => Row(
    children: [
      const AppIcon(AppIcons.loader, size: 20),
      const SizedBox(width: AppSpacing.xs),
      Expanded(child: _message(text)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    return AppPaneModalOverlay(
      barrierDismissible: false,
      onDismiss: () => unawaited(_finish()),
      child: _content(readiness),
    );
  }

  Widget _content(LedgerAppReadinessState readiness) {
    if (_phase == _Phase.cancelling) {
      return LedgerModalContent(
        title: _stoppingSearch ? 'Stopping search' : 'Cancelling request',
        child: _pending(
          _stoppingSearch
              ? 'Returning to connection options…'
              : 'Keep Ledger connected until the current request is cancelled.',
        ),
      );
    }
    if (_accessRecovery && widget.service is LedgerBluetoothAccess) {
      return LedgerBluetoothSession(
        service: widget.service,
        onRetry: _search,
        onClose: () => unawaited(_finish()),
        retryLabel: 'Find Ledger',
        builder: (context, model) => LedgerModalContent(
          title: model.title,
          onBack: () => unawaited(_finish()),
          footer: model.restricted
              ? Center(
                  child: AppButton(
                    size: AppButtonSize.mediumLarge,
                    minWidth: kAppModalButtonMinWidth,
                    onPressed: model.onAction,
                    child: const Text('Close'),
                  ),
                )
              : _footer(label: model.label, action: model.onAction),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              model.busy ? _pending(model.message) : _message(model.message),
              LedgerBluetoothRestrictedHelp(model: model),
            ],
          ),
        ),
      );
    }
    final failed = _phase == _Phase.failed;
    if (_choosing && !failed) {
      return LedgerModalContent(
        title: 'Find Ledger',
        identity: 'Bluetooth connection',
        onBack: () => unawaited(_finish()),
        footer: _phase == _Phase.empty
            ? _footer(label: 'Search again', action: _search)
            : _footer(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_phase == _Phase.empty)
              _message(
                'No Ledger found. Unlock Ledger, enable Bluetooth and keep it nearby. Then search again.',
              )
            else ...[
              for (final device in _devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: AppButton(
                    key: ValueKey('ledger_desktop_ble_device_${device.id}'),
                    variant: AppButtonVariant.secondary,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    expand: true,
                    constrainContent: true,
                    growWithContent: true,
                    height: 54,
                    onPressed: () => _read(device),
                    child: Row(
                      children: [
                        const AppIcon(AppIcons.ledger, size: 20),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(child: Text(ledgerDeviceLabel(device))),
                        const AppIcon(AppIcons.chevronForward, size: 16),
                      ],
                    ),
                  ),
                ),
              if (_phase == _Phase.preparing) ...[
                _pending('Checking Bluetooth access…'),
                const SizedBox(height: AppSpacing.s),
                _message(
                  'macOS may ask for Bluetooth access. If prompted, allow access for Vizor.',
                ),
              ] else if (_discovering || _phase == _Phase.scanning)
                _pending('Searching for nearby Ledgers…'),
            ],
          ],
        ),
      );
    }
    final procedure = !failed || (_declined && !_cleanupFailed);
    final opening = readiness.phase == LedgerAppReadinessPhase.confirmOpening;
    final current = _bluetooth && _phase == _Phase.connecting
        ? 0
        : _declinedStep ??
              (opening
                  ? 1
                  : readiness.phase == LedgerAppReadinessPhase.ready
                  ? 2
                  : _resumingStep ?? 1);
    return LedgerModalContent(
      title: procedure ? 'Connect Ledger' : 'Could not connect Ledger',
      identity:
          '${_device == null ? 'Ledger' : ledgerDeviceLabel(_device!)} · ${_bluetooth ? 'Bluetooth' : 'USB'}',
      onBack: () => unawaited(_finish(reselect: _device != null)),
      backLabel: 'Choose another Ledger',
      footer: failed
          ? _footer(
              label: !_cleanupFailed && !_retryable ? 'Back' : 'Try again',
              action: _cleanupFailed
                  ? () => unawaited(_finish(reselect: _reselectAfterCleanup))
                  : !_retryable
                  ? () => unawaited(_finish())
                  : _choosing
                  ? _search
                  : () => _read(),
            )
          : _footer(),
      child: procedure
          ? LedgerProcedure(
              topPadding: 0,
              currentStep: current,
              steps: [
                LedgerStep(
                  'Connect Ledger',
                  message: current == 0
                      ? 'Keep your Ledger nearby and unlocked, with Bluetooth turned on.'
                      : null,
                  busy: current == 0 && !failed,
                ),
                LedgerStep(
                  'Open Zcash',
                  message: current == 1
                      ? _declinedStep == 1
                            ? _error
                            : opening
                            ? 'Confirm opening Zcash on Ledger.'
                            : 'Vizor is checking the Zcash app.'
                      : null,
                  note: current == 1 && !failed ? 'Keep Zcash open.' : null,
                  busy: current == 1 && !failed,
                  requiresDeviceAction: opening && !failed,
                ),
                LedgerStep(
                  'Approve viewing key',
                  message: _declinedStep == 2
                      ? _error
                      : ledgerViewingKeyApprovalMessage(
                          widget.accountIndex,
                          readiness.version,
                        ),
                  busy: current == 2 && !failed,
                  requiresDeviceAction: !failed,
                ),
              ],
            )
          : _message(_error!),
    );
  }
}
