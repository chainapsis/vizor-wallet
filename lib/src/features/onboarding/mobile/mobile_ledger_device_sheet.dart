import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';

Future<LedgerBleDevice?> showMobileLedgerDeviceSheet({
  required BuildContext context,
  required LedgerMobileBleService service,
}) async {
  try {
    return await showAppMobileSheet<LedgerBleDevice>(
      context: context,
      builder: (sheetContext) => MobileLedgerDeviceSheet(
        service: service,
        onSelected: (device) => Navigator.of(sheetContext).pop(device),
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  } finally {
    await _bestEffortStopDiscovery(service);
  }
}

Future<void> _bestEffortStopDiscovery(LedgerMobileBleService service) async {
  try {
    await service.stopDiscovery();
  } catch (_) {
    // The selection path already stops discovery before connecting. Cleanup
    // after dismissal must not replace a successful selection with an error.
  }
}

class MobileLedgerDeviceSheet extends StatefulWidget {
  const MobileLedgerDeviceSheet({
    required this.service,
    required this.onSelected,
    required this.onClose,
    super.key,
  });

  final LedgerMobileBleService service;
  final ValueChanged<LedgerBleDevice> onSelected;
  final VoidCallback onClose;

  @override
  State<MobileLedgerDeviceSheet> createState() =>
      _MobileLedgerDeviceSheetState();
}

enum _DiscoveryState { requestingPermission, scanning, empty, failed }

class _MobileLedgerDeviceSheetState extends State<MobileLedgerDeviceSheet> {
  StreamSubscription<LedgerDiscoveryUpdate>? _subscription;
  _DiscoveryState _state = _DiscoveryState.requestingPermission;
  List<LedgerBleDevice> _devices = const [];
  String? _error;
  String? _connectingDeviceId;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_startDiscovery());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription?.cancel());
    unawaited(_bestEffortStopDiscovery(widget.service));
    super.dispose();
  }

  Future<void> _stopDiscovery() async {
    final subscription = _subscription;
    _subscription = null;
    // Request cancellation immediately, but do not make connect/retry depend
    // on a platform event stream acknowledging cancellation. The native stop
    // below is the authoritative discovery boundary; generations ignore any
    // event already queued for the old subscription.
    unawaited(subscription?.cancel());
    await widget.service.stopDiscovery();
  }

  Future<void> _startDiscovery() async {
    final generation = ++_generation;
    try {
      await _stopDiscovery();
      // A connected Ledger no longer advertises itself, so starting another
      // scan while retaining the previous picker session can hide that device.
      // Entering this sheet starts a fresh device-selection session.
      await widget.service.disconnect();
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = _DiscoveryState.requestingPermission;
        _devices = const [];
        _error = null;
        _connectingDeviceId = null;
      });
      final granted = await widget.service.requestPermissions();
      if (!mounted || generation != _generation) return;
      if (!granted) {
        setState(() {
          _state = _DiscoveryState.failed;
          _error =
              'Bluetooth permission is required to find your Ledger. Allow it in Settings, then try again.';
        });
        return;
      }
      setState(() => _state = _DiscoveryState.scanning);
      _subscription = widget.service.discoverDevices().listen(
        (update) => _handleUpdate(generation, update),
        onError: (Object error) => _handleFailure(generation, error),
      );
    } catch (error) {
      _handleFailure(generation, error);
    }
  }

  void _handleUpdate(int generation, LedgerDiscoveryUpdate update) {
    if (!mounted || generation != _generation) return;
    switch (update) {
      case LedgerDevicesDiscovered(:final devices):
        setState(() {
          _devices = devices;
          _state = _DiscoveryState.scanning;
        });
      case LedgerDiscoveryEnded():
        setState(() {
          _state = _devices.isEmpty
              ? _DiscoveryState.empty
              : _DiscoveryState.scanning;
        });
      case LedgerDiscoveryFailed(:final error):
        _handleFailure(generation, error);
    }
  }

  void _handleFailure(int generation, Object error) {
    if (!mounted || generation != _generation) return;
    final message = switch (error) {
      LedgerMobileException(failure: LedgerMobileFailure.bluetoothOff) =>
        'Turn on Bluetooth, then try again.',
      LedgerMobileException(failure: LedgerMobileFailure.permissionDenied) =>
        'Bluetooth permission is required to find your Ledger. Allow it in Settings, then try again.',
      LedgerMobileException(:final message) => message,
      _ => 'Vizor could not find Ledger devices. Try again.',
    };
    setState(() {
      _state = _DiscoveryState.failed;
      _error = message;
      _connectingDeviceId = null;
    });
  }

  Future<void> _connect(LedgerBleDevice device) async {
    if (_connectingDeviceId != null) return;
    setState(() {
      _connectingDeviceId = device.id;
      _error = null;
    });
    try {
      await _stopDiscovery();
      await widget.service.connect(device);
      if (!mounted) return;
      widget.onSelected(device);
    } catch (error) {
      _handleFailure(_generation, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final busy = _connectingDeviceId != null;
    return MobileModalScaffold(
      key: const ValueKey('mobile_ledger_device_sheet'),
      title: 'Select your Ledger',
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Unlock your Ledger, turn on Bluetooth, and keep it nearby.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_devices.isNotEmpty)
            ..._devices.map(
              (device) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _LedgerDeviceRow(
                  device: device,
                  connecting: _connectingDeviceId == device.id,
                  enabled: !busy,
                  onTap: () => unawaited(_connect(device)),
                ),
              ),
            )
          else if (_state == _DiscoveryState.requestingPermission ||
              _state == _DiscoveryState.scanning)
            const _StatusMessage(
              key: ValueKey('mobile_ledger_scanning'),
              iconName: AppIcons.loader,
              title: 'Scanning for Ledger devices',
              message: 'This can take a few seconds.',
            )
          else if (_state == _DiscoveryState.empty)
            const _StatusMessage(
              key: ValueKey('mobile_ledger_empty'),
              iconName: AppIcons.search,
              title: 'No Ledger devices found',
              message: 'Check that your Ledger is unlocked and try again.',
            )
          else
            _StatusMessage(
              key: const ValueKey('mobile_ledger_discovery_error'),
              iconName: AppIcons.warningCircle,
              title: 'Could not find your Ledger',
              message: _error ?? 'Try again.',
            ),
          if (_state == _DiscoveryState.empty ||
              _state == _DiscoveryState.failed) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const ValueKey('mobile_ledger_discovery_retry'),
              onPressed: busy ? null : () => unawaited(_startDiscovery()),
              variant: AppButtonVariant.secondary,
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LedgerDeviceRow extends StatelessWidget {
  const _LedgerDeviceRow({
    required this.device,
    required this.connecting,
    required this.enabled,
    required this.onTap,
  });

  final LedgerBleDevice device;
  final bool connecting;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${device.name}, ${device.model}',
      child: GestureDetector(
        key: ValueKey('mobile_ledger_device_${device.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Row(
            children: [
              AppIcon(
                connecting ? AppIcons.loader : AppIcons.ledger,
                size: 20,
                color: colors.icon.regular,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connecting ? 'Connecting to ${device.name}' : device.name,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    Text(
                      device.model,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const AppIcon(AppIcons.chevronForward, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.iconName,
    required this.title,
    required this.message,
    super.key,
  });

  final String iconName;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        children: [
          AppIcon(iconName, size: 20, color: colors.icon.muted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
