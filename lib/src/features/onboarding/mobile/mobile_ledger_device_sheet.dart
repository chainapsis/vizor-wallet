import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../../ledger/ledger_device_label.dart';
import '../../ledger/services/ledger_bluetooth_access.dart';
import '../../ledger/widgets/mobile/mobile_ledger_bluetooth_content.dart';
import '../../ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import '../../ledger/widgets/mobile/mobile_ledger_connection_help.dart';
import '../../ledger/widgets/mobile/mobile_ledger_help_navigation.dart';
import '../../ledger/services/ledger_failure_guidance.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_button.dart';
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
  bool _bluetoothRecovery = false;
  String? _connectingDeviceId;
  var _generation = 0;
  bool _closing = false;
  bool _connectionTransferred = false;
  bool _help = false;
  bool _openingHelp = false;
  bool _settingsBusy = false;
  String? _helpError;
  final _helpNavigation = MobileLedgerHelpNavigation();

  bool _isCurrent(int generation) =>
      mounted && !_closing && generation == _generation;

  @override
  void initState() {
    super.initState();
    unawaited(_startDiscovery());
  }

  @override
  void dispose() {
    _abandonConnection();
    unawaited(_subscription?.cancel());
    unawaited(_bestEffortStopDiscovery(widget.service));
    super.dispose();
  }

  void _abandonConnection() {
    _closing = true;
    _generation++;
    if (_connectingDeviceId != null && !_connectionTransferred) {
      _connectingDeviceId = null;
      unawaited(_cancelConnection());
    }
  }

  Future<void> _cancelConnection() async {
    try {
      await widget.service.cancelSigning();
    } catch (_) {
      // The dismissed picker must not publish native cancellation failures.
    }
  }

  void _close() {
    _abandonConnection();
    widget.onClose();
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
      if (!_isCurrent(generation)) return;
      // A connected Ledger no longer advertises itself, so starting another
      // scan while retaining the previous picker session can hide that device.
      // Entering this sheet starts a fresh device-selection session.
      await widget.service.disconnect();
      if (!_isCurrent(generation)) return;
      setState(() {
        _state = _DiscoveryState.requestingPermission;
        _devices = const [];
        _error = null;
        _bluetoothRecovery = false;
        _connectingDeviceId = null;
        _help = false;
        _helpError = null;
      });
      final granted = await prepareLedgerBluetoothDiscovery(widget.service);
      if (!_isCurrent(generation)) return;
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

  Future<void> _openHelp() async {
    if (_openingHelp ||
        _settingsBusy ||
        _connectingDeviceId != null ||
        _closing) {
      return;
    }
    final generation = ++_generation;
    setState(() => _openingHelp = true);
    try {
      await _stopDiscovery();
      if (!_isCurrent(generation)) return;
      setState(() {
        _help = true;
        _helpError = null;
      });
    } catch (error) {
      _handleFailure(generation, error);
    } finally {
      if (_isCurrent(generation)) setState(() => _openingHelp = false);
    }
  }

  Future<void> _openPairingSettings() async {
    if (_settingsBusy ||
        _closing ||
        widget.service is! LedgerBluetoothPairingSettings) {
      return;
    }
    final generation = _generation;
    setState(() {
      _settingsBusy = true;
      _helpError = null;
    });
    try {
      final opened = await (widget.service as LedgerBluetoothPairingSettings)
          .openBluetoothPairingSettings();
      if (!_isCurrent(generation)) return;
      if (!opened) {
        setState(
          () => _helpError =
              'Open Bluetooth settings manually to remove the old pairing.',
        );
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        setState(
          () => _helpError =
              'Open Bluetooth settings manually to remove the old pairing.',
        );
      }
    } finally {
      if (_isCurrent(generation)) setState(() => _settingsBusy = false);
    }
  }

  void _handleUpdate(int generation, LedgerDiscoveryUpdate update) {
    if (!_isCurrent(generation)) return;
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
    if (!_isCurrent(generation)) return;
    final message =
        ledgerFailureGuidance(error)?.message ??
        'Vizor could not find Ledger devices. Try again.';
    setState(() {
      _state = _DiscoveryState.failed;
      _error = message;
      _bluetoothRecovery =
          ledgerFailureGuidance(error)?.bluetoothRecovery ?? false;
      _connectingDeviceId = null;
    });
  }

  Future<void> _connect(LedgerBleDevice device) async {
    if (_closing || _connectingDeviceId != null) return;
    final generation = ++_generation;
    setState(() {
      _connectingDeviceId = device.id;
      _error = null;
    });
    try {
      await _stopDiscovery();
      if (!_isCurrent(generation)) return;
      await requireLedgerBluetoothAccess(widget.service);
      if (!mounted || generation != _generation) return;
      await widget.service.connect(device);
      if (!_isCurrent(generation)) return;
      // Successful selection transfers the connection to the parent screen.
      _connectionTransferred = true;
      widget.onSelected(device);
    } catch (error) {
      _handleFailure(generation, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final busy = _connectingDeviceId != null || _openingHelp || _settingsBusy;
    final parentHelpNavigation = MobileLedgerHelpScope.maybeOf(context);
    final recovery =
        _state == _DiscoveryState.failed &&
        _bluetoothRecovery &&
        widget.service is LedgerBluetoothAccess;
    return PopScope<Object?>(
      canPop: parentHelpNavigation != null || !_help,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _abandonConnection();
        if (!didPop && _help && parentHelpNavigation == null) {
          _helpNavigation.previous();
        }
      },
      child: MobileLedgerHelpScope(
        navigation: parentHelpNavigation ?? _helpNavigation,
        child: _help
            ? MobileLedgerConnectionHelp(
                platform: defaultTargetPlatform,
                busy: _settingsBusy,
                error: _helpError,
                onBack: () => setState(() => _help = false),
                onClose: _close,
                onSearch: () => unawaited(_startDiscovery()),
                onSettings: widget.service is LedgerBluetoothPairingSettings
                    ? () => unawaited(_openPairingSettings())
                    : null,
              )
            : recovery
            ? MobileLedgerBluetoothContent(
                key: const ValueKey('mobile_ledger_device_sheet'),
                service: widget.service,
                onRetry: () => unawaited(_startDiscovery()),
                onClose: _close,
                retryLabel: 'Find my Ledger',
                purpose: 'continue',
              )
            : MobileLedgerSheetContent(
                key: const ValueKey('mobile_ledger_device_sheet'),
                title: 'Add Ledger account',
                onClose: _close,
                action:
                    _state == _DiscoveryState.empty ||
                        _state == _DiscoveryState.failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MobileLedgerAction(
                            _state == _DiscoveryState.empty
                                ? 'Search again'
                                : 'Try again',
                            key: const ValueKey(
                              'mobile_ledger_discovery_retry',
                            ),
                            onPressed: busy
                                ? null
                                : () => unawaited(_startDiscovery()),
                          ),
                          if (_state == _DiscoveryState.empty)
                            AppButton(
                              variant: AppButtonVariant.ghost,
                              expand: true,
                              growWithContent: true,
                              constrainContent: true,
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_openHelp()),
                              child: const Text('Connection help'),
                            ),
                        ],
                      )
                    : null,
                children: [
                  Text(
                    _devices.isNotEmpty
                        ? 'Select your Ledger.'
                        : 'Unlock Ledger, turn on Bluetooth, and keep it nearby.',
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
                      title: 'Searching for Ledger devices…',
                      message: 'This can take a few seconds.',
                    )
                  else if (_state == _DiscoveryState.empty)
                    const _StatusMessage(
                      key: ValueKey('mobile_ledger_empty'),
                      iconName: AppIcons.search,
                      title: 'No Ledger devices found',
                      message:
                          'Check that your Ledger is unlocked and try again.',
                    ),
                  if (_state == _DiscoveryState.failed)
                    _StatusMessage(
                      key: const ValueKey('mobile_ledger_discovery_error'),
                      iconName: AppIcons.warningCircle,
                      title: 'Could not connect to your Ledger',
                      message: _error ?? 'Try again.',
                    ),
                ],
              ),
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
      child: AppButton(
        key: ValueKey('mobile_ledger_device_${device.id}'),
        onPressed: enabled ? onTap : null,
        variant: AppButtonVariant.secondary,
        height: 52,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        enabledBackgroundColor: colors.background.neutralSubtleOpacity,
        enabledBorderColor: const Color(0x00000000),
        expand: true,
        growWithContent: true,
        constrainContent: true,
        leading: ExcludeSemantics(
          child: AppIcon(
            connecting ? AppIcons.loader : AppIcons.ledger,
            animated: connecting,
            size: 20,
          ),
        ),
        trailing: const ExcludeSemantics(
          child: AppIcon(AppIcons.chevronForward, size: 20),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            connecting
                ? 'Connecting to ${ledgerDeviceLabel(device)}'
                : ledgerDeviceLabel(device),
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
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
          AppIcon(
            iconName,
            animated: iconName == AppIcons.loader,
            size: 20,
            color: colors.icon.regular,
          ),
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
