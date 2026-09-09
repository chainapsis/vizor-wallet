import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/content_overlay_inset.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../ledger/ledger_capability.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';

Future<LedgerDeviceAccount?> showLedgerDesktopBleConnectDialog({
  required BuildContext context,
  required LedgerMobileBleService service,
  required LedgerBluetoothAccountConnector connector,
  required int accountIndex,
  bool Function(Object error)? onAccountError,
}) async {
  final appTheme = AppTheme.of(context);
  final platform = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(ledgerTargetPlatformProvider);
  final account = await showDialog<LedgerDeviceAccount>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    builder: (dialogContext) => AppTheme(
      data: appTheme,
      child: ValueListenableBuilder<double>(
        valueListenable: contentOverlayLeftInset,
        builder: (_, leftInset, child) => Padding(
          padding: EdgeInsets.fromLTRB(
            leftInset,
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Stack(
            key: const ValueKey('ledger_desktop_ble_modal_pane'),
            fit: StackFit.expand,
            children: [
              AppPaneModalOverlay(
                // Closing stays explicit while device operations are active.
                onDismiss: () {},
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: child!,
                ),
              ),
            ],
          ),
        ),
        child: _LedgerDesktopBleConnectDialog(
          service: service,
          connector: connector,
          accountIndex: accountIndex,
          platform: platform,
          onAccountError: onAccountError,
          onConnected: (account) => Navigator.of(dialogContext).pop(account),
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
  if (account == null) {
    await _bestEffortDisconnect(service);
  }
  return account;
}

Future<void> _bestEffortDisconnect(LedgerMobileBleService service) async {
  try {
    await service.stopDiscovery();
  } catch (_) {
    // The probe result is already visible; cleanup must not replace it.
  }
  try {
    await service.disconnect();
  } catch (_) {
    // The device may already have disconnected while switching apps.
  }
}

enum _ProbePhase {
  preparing,
  scanning,
  devices,
  connecting,
  readingAccount,
  ready,
  empty,
  failed,
}

class _LedgerDesktopBleConnectDialog extends StatefulWidget {
  const _LedgerDesktopBleConnectDialog({
    required this.service,
    required this.connector,
    required this.accountIndex,
    required this.platform,
    required this.onConnected,
    required this.onClose,
    this.onAccountError,
  });

  final LedgerMobileBleService service;
  final LedgerBluetoothAccountConnector connector;
  final int accountIndex;
  final TargetPlatform platform;
  final ValueChanged<LedgerDeviceAccount> onConnected;
  final VoidCallback onClose;
  // Returning true hands a form-level error back to the caller and closes the
  // dialog. Transport errors stay in the dialog unless explicitly handled.
  final bool Function(Object error)? onAccountError;

  @override
  State<_LedgerDesktopBleConnectDialog> createState() =>
      _LedgerDesktopBleConnectDialogState();
}

class _LedgerDesktopBleConnectDialogState
    extends State<_LedgerDesktopBleConnectDialog> {
  StreamSubscription<LedgerDiscoveryUpdate>? _subscription;
  _ProbePhase _phase = _ProbePhase.preparing;
  List<LedgerBleDevice> _devices = const [];
  LedgerBleDevice? _connectedDevice;
  LedgerDeviceAccount? _account;
  String? _error;
  var _generation = 0;

  bool get _busy =>
      _phase == _ProbePhase.preparing ||
      _phase == _ProbePhase.scanning ||
      _phase == _ProbePhase.connecting ||
      _phase == _ProbePhase.readingAccount;

  @override
  void initState() {
    super.initState();
    unawaited(_startDiscovery());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription?.cancel());
    unawaited(widget.service.stopDiscovery().catchError((_) {}));
    super.dispose();
  }

  Future<void> _stopDiscovery() async {
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    await widget.service.stopDiscovery();
  }

  Future<void> _startDiscovery() async {
    final generation = ++_generation;
    try {
      await _stopDiscovery();
      await widget.service.disconnect();
      if (!mounted || generation != _generation) return;
      setState(() {
        _phase = _ProbePhase.preparing;
        _devices = const [];
        _connectedDevice = null;
        _account = null;
        _error = null;
      });

      final granted = await widget.service.requestPermissions();
      if (!mounted || generation != _generation) return;
      if (!granted) {
        _fail(
          'Bluetooth permission is required. Allow Vizor in System Settings, then try again.',
        );
        return;
      }

      setState(() => _phase = _ProbePhase.scanning);
      _subscription = widget.service.discoverDevices().listen(
        (update) => _handleDiscovery(generation, update),
        onError: (Object error) => _handleError(generation, error),
      );
    } catch (error) {
      _handleError(generation, error);
    }
  }

  void _handleDiscovery(int generation, LedgerDiscoveryUpdate update) {
    if (!mounted || generation != _generation) return;
    switch (update) {
      case LedgerDevicesDiscovered(:final devices):
        setState(() {
          _devices = devices;
          _phase = devices.isEmpty ? _ProbePhase.scanning : _ProbePhase.devices;
        });
      case LedgerDiscoveryEnded():
        setState(() {
          _phase = _devices.isEmpty ? _ProbePhase.empty : _ProbePhase.devices;
        });
      case LedgerDiscoveryFailed(:final error):
        _handleError(generation, error);
    }
  }

  Future<void> _connect(LedgerBleDevice device) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _phase = _ProbePhase.connecting;
      _connectedDevice = device;
      _error = null;
    });
    try {
      await _stopDiscovery();
      await widget.service.connect(device);
      if (!mounted || generation != _generation) return;
      setState(() => _phase = _ProbePhase.readingAccount);
      final account = await widget.connector(widget.accountIndex, device);
      if (!mounted || generation != _generation) return;
      setState(() {
        _account = account;
        _phase = _ProbePhase.ready;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (widget.onAccountError?.call(error) ?? false) {
        widget.onClose();
        return;
      }
      _handleError(generation, error);
    }
  }

  void _handleError(int generation, Object error) {
    if (!mounted || generation != _generation) return;
    final message = switch (error) {
      LedgerMobileException(:final message) => message,
      LedgerAppReadinessException(:final message) => message,
      UnsupportedError() =>
        'Update the Ledger Zcash app to version $kMinimumLedgerZcashAppVersion or newer.',
      _ => 'Vizor could not connect to this Ledger over Bluetooth. Try again.',
    };
    _fail(message);
  }

  void _fail(String message) {
    setState(() {
      _phase = _ProbePhase.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AppModalCard(
        key: const ValueKey('ledger_desktop_ble_connect_dialog'),
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose your Ledger',
                textAlign: TextAlign.center,
                style: AppTypography.headlineMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Unlock your Ledger, turn on Bluetooth, and keep it nearby.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _buildBody(context),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Bluetooth is available on Ledger ${ledgerBluetoothSupportedModels(widget.platform)}.',
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.secondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Visibility(
                    visible:
                        _phase == _ProbePhase.empty ||
                        _phase == _ProbePhase.failed ||
                        _phase == _ProbePhase.ready,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: AppButton(
                      expand: true,
                      constrainContent: true,
                      key: ValueKey(
                        _phase == _ProbePhase.ready
                            ? 'ledger_desktop_ble_continue'
                            : 'ledger_desktop_ble_retry',
                      ),
                      onPressed: _phase == _ProbePhase.ready
                          ? () => widget.onConnected(_account!)
                          : _busy
                          ? null
                          : () => unawaited(_startDiscovery()),
                      child: Text(
                        _phase == _ProbePhase.ready ? 'Continue' : 'Try again',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    key: const ValueKey('ledger_desktop_ble_close'),
                    expand: true,
                    constrainContent: true,
                    onPressed: widget.onClose,
                    variant: AppButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_phase == _ProbePhase.devices) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.3,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final device in _devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _DeviceRow(
                    device: device,
                    onTap: () => unawaited(_connect(device)),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final (icon, title, message) = switch (_phase) {
      _ProbePhase.preparing => (
        AppIcons.loader,
        'Preparing Bluetooth',
        widget.platform == TargetPlatform.windows
            ? 'Windows may ask for Bluetooth permission and pairing confirmation.'
            : 'macOS may ask for Bluetooth permission.',
      ),
      _ProbePhase.scanning => (
        AppIcons.loader,
        'Scanning for Ledger devices',
        'This can take a few seconds.',
      ),
      _ProbePhase.connecting => (
        AppIcons.loader,
        'Connecting to ${_connectedDevice?.name ?? 'Ledger'}',
        'Approve Bluetooth pairing on the device if prompted.',
      ),
      _ProbePhase.readingAccount => (
        AppIcons.loader,
        'Approve on your Ledger',
        'Confirm opening Zcash and approve the viewing-key request on your Ledger.',
      ),
      _ProbePhase.ready => (
        AppIcons.checkCircle,
        '${_connectedDevice?.name ?? 'Ledger'} is ready',
        'Your viewing key was shared. Continue to finish adding your account.',
      ),
      _ProbePhase.empty => (
        AppIcons.search,
        'No Ledger devices found',
        'Check Bluetooth and make sure the Ledger is unlocked.',
      ),
      _ProbePhase.failed => (
        AppIcons.ledger,
        'Let’s reconnect',
        _error ?? 'Try again.',
      ),
      _ProbePhase.devices => throw StateError('Device list handled above'),
    };

    return Padding(
      key: ValueKey('ledger_desktop_ble_${_phase.name}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          AppIcon(icon, size: 32, color: context.colors.text.secondary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onTap});

  final LedgerBleDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: ValueKey('ledger_desktop_ble_device_${device.id}'),
      onPressed: onTap,
      variant: AppButtonVariant.secondary,
      expand: true,
      constrainContent: true,
      leading: const AppIcon(AppIcons.ledger),
      child: Text('${device.name}  ·  ${device.model}'),
    );
  }
}
