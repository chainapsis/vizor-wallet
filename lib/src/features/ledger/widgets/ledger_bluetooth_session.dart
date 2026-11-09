import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../services/ledger_bluetooth_access.dart';
import '../services/ledger_device_request.dart';
import '../services/ledger_failure_guidance.dart';
import '../services/ledger_mobile_ble_service.dart';

/// Only refreshes access. Reconnecting/signing always requires the caller's
/// explicit retry action, including after returning from system Settings.
class LedgerBluetoothSession extends ConsumerStatefulWidget {
  const LedgerBluetoothSession({
    required this.builder,
    this.service,
    this.onRetry,
    this.onClose,
    this.onBusyChanged,
    this.retryLabel,
    this.enabled = true,
    super.key,
  });
  final Widget Function(BuildContext, LedgerBluetoothPresentation) builder;
  final bool enabled;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onBusyChanged;
  final String? retryLabel;
  final LedgerMobileBleService? service;

  @override
  ConsumerState<LedgerBluetoothSession> createState() =>
      _LedgerBluetoothSessionState();
}

class _LedgerBluetoothSessionState extends ConsumerState<LedgerBluetoothSession>
    with WidgetsBindingObserver {
  LedgerBluetoothAccessStatus? _status;
  bool _busy = false;
  bool _requestAttempted = false;
  String? _error;
  bool _refreshPending = false;
  bool _invalidated = false;
  void Function()? _check;

  LedgerMobileBleService get _service =>
      widget.service ?? ref.read(ledgerMobileBleServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_busy) {
      _refreshPending = true;
    } else {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool request = false, bool settings = false}) async {
    if (_busy || !mounted || _invalidated) return;
    final service = _service;
    if (service is! LedgerBluetoothAccess) return;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      _check ??= ref.read(ledgerDeviceRequestsProvider).capture();
      _check!();
      final access = service as LedgerBluetoothAccess;
      if (request) {
        _requestAttempted = true;
        await service.requestPermissions();
        _check!();
        if (!mounted) return;
      }
      String? error;
      if (settings) {
        final opened = await access.openBluetoothSettings();
        _check!();
        if (!mounted) return;
        if (!opened) {
          final l10n = context.l10n;
          error = _status?.permission == LedgerBluetoothPermission.restricted
              ? l10n.ledgerBtCouldNotOpenSettingsRestricted
              : l10n.ledgerBtCouldNotOpenSettingsAllow;
        }
      }
      final status = await access.bluetoothAccessStatus();
      _check!();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = error;
      });
    } catch (error) {
      if (_check == null) {
        _invalidated = true;
        return;
      }
      // Account changes and wallet locking invalidate the captured request.
      try {
        _check?.call();
      } catch (_) {
        _invalidated = true;
        return;
      }
      if (mounted) {
        final l10n = context.l10n;
        setState(
          () => _error =
              ledgerFailureGuidance(l10n, error)?.message ??
              l10n.ledgerBtCouldNotCheckAccess,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(_refresh());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_service is! LedgerBluetoothAccess) return const SizedBox.shrink();
    final status = _status;
    final granted = status?.granted == true;
    final radioOff = granted && status?.bluetoothEnabled == false;
    final locationOff = granted && status?.locationEnabled == false;
    final restricted =
        status?.permission == LedgerBluetoothPermission.restricted;
    final requestable =
        status?.permission == LedgerBluetoothPermission.requestable &&
        !_requestAttempted;
    final ready = granted && !radioOff && !locationOff;
    final l10n = context.l10n;
    final title = status == null
        ? l10n.ledgerBtTitleChecking
        : radioOff
        ? l10n.ledgerBtTitleTurnOnBluetooth
        : locationOff
        ? l10n.ledgerBtTitleTurnOnLocation
        : restricted
        ? l10n.ledgerBtTitleRestricted
        : ready
        ? l10n.ledgerBtTitleReady
        : requestable
        ? (status.locationPermission
              ? l10n.ledgerBtTitleAllowLocation
              : l10n.ledgerBtTitleAllowBluetooth)
        : (status.locationPermission
              ? l10n.ledgerBtTitleAllowLocationSettings
              : l10n.ledgerBtTitleAllowBluetoothSettings);
    final message =
        (restricted && _error != null
            ? '${status!.message(l10n)}\n\n$_error'
            : _error) ??
        (ready
            ? l10n.ledgerBtMsgReady
            : requestable
            ? (status!.locationPermission
                  ? l10n.ledgerBtMsgLocationNeeded
                  : l10n.ledgerBtMsgBluetoothNeeded)
            : (_requestAttempted &&
                          status?.permission ==
                              LedgerBluetoothPermission.requestable
                      ? LedgerBluetoothAccessStatus(
                          LedgerBluetoothPermission.settings,
                          locationPermission: status!.locationPermission,
                          macOS: status.macOS,
                        ).message(l10n)
                      : status?.message(l10n)) ??
                  l10n.ledgerBtMsgChecking);
    final label = _busy
        ? l10n.ledgerBtLabelChecking
        : restricted
        ? l10n.commonClose
        : _error != null || status == null
        ? l10n.commonCheckAgain
        : radioOff || locationOff
        ? l10n.commonCheckAgain
        : ready
        ? (widget.retryLabel ?? l10n.ledgerBtLabelReconnect)
        : requestable
        ? l10n.ledgerBtLabelAllowAccess
        : l10n.commonOpenSettings;
    bool canAct() {
      if (!mounted || !widget.enabled || _busy || _invalidated) return false;
      try {
        _check?.call();
        return true;
      } catch (_) {
        _invalidated = true;
        return false;
      }
    }

    void action() {
      if (!canAct()) return;
      if (restricted) {
        widget.onClose?.call();
      } else if (_error != null || status == null || radioOff || locationOff) {
        unawaited(_refresh());
      } else if (ready) {
        widget.onRetry?.call();
      } else {
        unawaited(_refresh(request: requestable, settings: !requestable));
      }
    }

    return widget.builder(
      context,
      LedgerBluetoothPresentation(
        title: title,
        message: message,
        label: label,
        busy: _busy,
        ready: ready,
        hasError: _error != null,
        access: status,
        onOpenSettings: restricted && widget.enabled && !_busy && !_invalidated
            ? () {
                if (canAct()) unawaited(_refresh(settings: true));
              }
            : null,
        onAction:
            !widget.enabled ||
                _busy ||
                _invalidated ||
                (ready && widget.onRetry == null) ||
                (restricted && widget.onClose == null)
            ? null
            : action,
      ),
    );
  }
}

class LedgerBluetoothPresentation {
  const LedgerBluetoothPresentation({
    required this.title,
    required this.message,
    required this.label,
    required this.busy,
    required this.onAction,
    required this.ready,
    required this.hasError,
    required this.access,
    this.onOpenSettings,
  });
  final String title;
  final String message;
  final String label;
  final bool busy;
  final VoidCallback? onAction;
  final bool ready;
  final bool hasError;
  final LedgerBluetoothAccessStatus? access;
  final VoidCallback? onOpenSettings;
  bool get restricted =>
      access?.permission == LedgerBluetoothPermission.restricted;
}
