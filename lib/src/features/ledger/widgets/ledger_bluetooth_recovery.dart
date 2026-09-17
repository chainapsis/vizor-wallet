import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../services/ledger_bluetooth_access.dart';
import '../services/ledger_device_request.dart';
import '../services/ledger_failure_guidance.dart';
import '../services/ledger_mobile_ble_service.dart';

/// Only refreshes access. Reconnecting/signing always requires the caller's
/// explicit retry action, including after returning from system Settings.
class LedgerBluetoothRecovery extends ConsumerStatefulWidget {
  const LedgerBluetoothRecovery({
    this.service,
    this.onRetry,
    this.onClose,
    this.onBusyChanged,
    this.retryLabel = 'Reconnect',
    this.enabled = true,
    super.key,
  });
  final bool enabled;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onBusyChanged;
  final String retryLabel;
  final LedgerMobileBleService? service;

  @override
  ConsumerState<LedgerBluetoothRecovery> createState() =>
      _LedgerBluetoothRecoveryState();
}

class _LedgerBluetoothRecoveryState
    extends ConsumerState<LedgerBluetoothRecovery>
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
          error =
              'Could not open Settings. Open your device settings manually and allow access for Vizor.';
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
        setState(
          () => _error =
              ledgerFailureGuidance(error)?.message ??
              'Could not check access. Open Settings manually, then check again.',
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
    final title = status == null
        ? 'Checking Bluetooth access'
        : radioOff
        ? 'Turn on Bluetooth'
        : locationOff
        ? 'Turn on location services'
        : restricted
        ? 'Access is restricted'
        : ready
        ? 'Ready to reconnect'
        : requestable
        ? (status.locationPermission
              ? 'Allow location access'
              : 'Allow Bluetooth access')
        : (status.locationPermission
              ? 'Allow location in Settings'
              : 'Allow Bluetooth in Settings');
    final message =
        _error ??
        (ready
            ? 'Turn on your Ledger and unlock it to continue.'
            : requestable
            ? (status!.locationPermission
                  ? 'This Android version needs location access to find your Ledger.'
                  : 'Vizor needs Bluetooth access to connect to your Ledger.')
            : (_requestAttempted &&
                          status?.permission ==
                              LedgerBluetoothPermission.requestable
                      ? LedgerBluetoothAccessStatus(
                          LedgerBluetoothPermission.settings,
                          locationPermission: status!.locationPermission,
                          macOS: status.macOS,
                        ).message
                      : status?.message) ??
                  'Checking whether Vizor can connect to your Ledger.');
    final label = _busy
        ? 'Checking access'
        : _error != null || status == null
        ? 'Check again'
        : restricted
        ? 'Close'
        : radioOff || locationOff
        ? 'Check again'
        : ready
        ? widget.retryLabel
        : requestable
        ? 'Allow access'
        : 'Open settings';
    void action() {
      if (_error != null || status == null || radioOff || locationOff) {
        unawaited(_refresh());
      } else if (restricted) {
        widget.onClose?.call();
      } else if (ready) {
        widget.onRetry?.call();
      } else {
        unawaited(_refresh(request: requestable, settings: !requestable));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          onPressed:
              !widget.enabled ||
                  _busy ||
                  _invalidated ||
                  (ready && widget.onRetry == null) ||
                  (restricted && widget.onClose == null)
              ? null
              : action,
          expand: true,
          constrainContent: true,
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          child: Text(label),
        ),
      ],
    );
  }
}
