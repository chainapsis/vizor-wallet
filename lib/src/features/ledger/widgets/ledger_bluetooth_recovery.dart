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
  const LedgerBluetoothRecovery({this.service, super.key});
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
    try {
      _check ??= ref.read(ledgerDeviceRequestsProvider).capture();
      _check!();
      final access = service as LedgerBluetoothAccess;
      if (request) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null || status != null) ...[
          Text(
            _error ?? status!.message,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (status?.permission == LedgerBluetoothPermission.requestable) ...[
          AppButton(
            onPressed: _busy || _invalidated
                ? null
                : () => unawaited(_refresh(request: true)),
            variant: AppButtonVariant.secondary,
            child: const Text('Allow permission'),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (status != null &&
            !status.granted &&
            status.permission != LedgerBluetoothPermission.restricted) ...[
          AppButton(
            onPressed: _busy || _invalidated
                ? null
                : () => unawaited(_refresh(settings: true)),
            variant: AppButtonVariant.secondary,
            child: const Text('Open settings'),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        AppButton(
          onPressed: _busy || _invalidated ? null : () => unawaited(_refresh()),
          variant: AppButtonVariant.ghost,
          child: Text(_busy ? 'Checking access' : 'Check access'),
        ),
      ],
    );
  }
}
