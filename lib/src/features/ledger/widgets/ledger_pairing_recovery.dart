import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../ledger_capability.dart';
import '../services/ledger_bluetooth_access.dart';
import '../services/ledger_connection_service.dart';
import '../services/ledger_device_request.dart';
import '../services/ledger_failure_guidance.dart';
import '../services/ledger_mobile_ble_service.dart';
import '../services/ledger_pairing_recovery_service.dart';
import '../services/ledger_signing_service.dart';
import 'ledger_bluetooth_recovery.dart';

enum _Stage { failed, scanning, devices, verifying, saving, ready, mismatch }

class LedgerPairingRecovery extends ConsumerStatefulWidget {
  const LedgerPairingRecovery({
    required this.accountUuid,
    required this.onRetry,
    required this.onClose,
    required this.onBusyChanged,
    this.enabled = true,
    super.key,
  });
  final String accountUuid;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;

  @override
  ConsumerState<LedgerPairingRecovery> createState() =>
      _LedgerPairingRecoveryState();
}

class _LedgerPairingRecoveryState extends ConsumerState<LedgerPairingRecovery> {
  _Stage _stage = _Stage.failed;
  bool _expanded = false;
  bool _accessRecovery = false;
  bool _invalidated = false;
  bool _settingsBusy = false;
  String? _error;
  List<LedgerBleDevice> _devices = const [];
  StreamSubscription<LedgerDiscoveryUpdate>? _subscription;
  int _generation = 0;
  late final LedgerMobileBleService _mobile;
  late final LedgerOperationCanceller _cancel;
  late final void Function() _epoch;

  bool get _busy =>
      _stage == _Stage.scanning ||
      _stage == _Stage.verifying ||
      _stage == _Stage.saving ||
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

  void _notifyBusy() => widget.onBusyChanged(_busy);

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription?.cancel());
    if (_stage == _Stage.scanning || _stage == _Stage.devices) {
      unawaited(_stopQuietly());
    }
    if (_stage == _Stage.verifying) unawaited(_cancelQuietly());
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
          ? _Stage.mismatch
          : _Stage.failed;
      _devices = const [];
      _accessRecovery = ledgerFailureGuidance(error)?.bluetoothRecovery == true;
      _error =
          error is LedgerAccountMismatchException ||
              ledgerFailureGuidance(error)?.pairingRecovery == true
          ? null
          : ledgerFailureGuidance(error)?.message ??
                'Could not reconnect. Try finding your Ledger again.';
    });
    _notifyBusy();
  }

  Future<void> _scan() async {
    if (_busy || !widget.enabled || _invalidated) return;
    final generation = ++_generation;
    setState(() {
      _stage = _Stage.scanning;
      _error = null;
      _devices = const [];
      _accessRecovery = false;
    });
    _notifyBusy();
    try {
      _check(generation);
      unawaited(_subscription?.cancel());
      _subscription = null;
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
      _check(generation);
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
                  _stage = _Stage.devices;
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
              _stage == _Stage.scanning) {
            setState(() => _stage = _Stage.devices);
            _notifyBusy();
          }
        },
      );
    } catch (error) {
      _fail(generation, error);
    }
  }

  Future<void> _select(LedgerBleDevice device) async {
    if ((_stage != _Stage.scanning && _stage != _Stage.devices) ||
        !widget.enabled ||
        _invalidated) {
      return;
    }
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    setState(() {
      _stage = _Stage.verifying;
      _error = null;
    });
    _notifyBusy();
    try {
      _check(generation);
      await ref
          .read(ledgerPairingRecoveryServiceProvider)
          .verifyAndSave(
            accountUuid: widget.accountUuid,
            device: device,
            checkCurrent: () => _check(generation),
            onSaving: () {
              setState(() => _stage = _Stage.saving);
              _notifyBusy();
            },
          );
      _check(generation);
      setState(() => _stage = _Stage.ready);
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

  @override
  Widget build(BuildContext context) {
    if (_accessRecovery) {
      return LedgerBluetoothRecovery(
        service: _mobile,
        onRetry: _scan,
        onClose: widget.onClose,
        retryLabel: 'Find my Ledger',
        enabled: widget.enabled,
        onBusyChanged: widget.onBusyChanged,
      );
    }
    final platform = ref.watch(ledgerTargetPlatformProvider);
    final settingsLink =
        platform != TargetPlatform.iOS &&
        _mobile is LedgerBluetoothPairingSettings;
    final title = switch (_stage) {
      _Stage.failed => 'Couldn’t connect to your Ledger',
      _Stage.scanning || _Stage.devices =>
        _devices.isEmpty
            ? (_stage == _Stage.scanning
                  ? 'Finding your Ledger'
                  : 'No Ledger devices found')
            : 'Select your Ledger',
      _Stage.verifying => 'Check your Ledger',
      _Stage.saving => 'Saving your connection',
      _Stage.ready => 'Your Ledger is connected',
      _Stage.mismatch => 'This Ledger doesn’t match',
    };
    final message = switch (_stage) {
      _Stage.failed =>
        'Unlock your Ledger and keep it nearby. Find it again to reconnect.',
      _Stage.scanning || _Stage.devices =>
        'Choose your Ledger. Vizor will check that it matches this account.',
      _Stage.verifying =>
        'Complete pairing if prompted, then open the Zcash app and approve sharing the viewing key.',
      _Stage.saving => 'Your account matches. Saving the verified connection.',
      _Stage.ready =>
        'Account verified. Continue when you’re ready to review the transaction on your Ledger.',
      _Stage.mismatch =>
        'Connect the Ledger that holds this account. Your saved connection hasn’t changed.',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          message,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        if (_stage == _Stage.failed) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: context.colors.background.neutralSubtleOpacity,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  expanded: _expanded,
                  child: AppButton(
                    key: const ValueKey('ledger_pairing_help'),
                    size: AppButtonSize.small,
                    height: 52,
                    contentPadding: EdgeInsets.zero,
                    variant: AppButtonVariant.ghost,
                    expand: true,
                    constrainContent: true,
                    onPressed: widget.enabled && !_busy
                        ? () => setState(() => _expanded = !_expanded)
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Did you reset pairing?',
                            style: AppTypography.bodySmall,
                          ),
                        ),
                        RotatedBox(
                          quarterTurns: _expanded ? 3 : 1,
                          child: const AppIcon(
                            AppIcons.chevronForward,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      children: [
                        _step(
                          '1',
                          'Remove the old pairing',
                          platform == TargetPlatform.iOS
                              ? 'Open Settings > Bluetooth. If your Ledger is listed, tap its info button and forget the device.'
                              : 'Open ${platform == TargetPlatform.macOS ? 'System Settings > Bluetooth' : 'Bluetooth settings'}. If your Ledger is listed, remove its saved pairing.',
                          settingsLink
                              ? AppButton(
                                  variant: AppButtonVariant.ghost,
                                  size: AppButtonSize.small,
                                  height: 44,
                                  contentPadding: EdgeInsets.zero,
                                  trailing: const AppIcon(
                                    AppIcons.arrowTopRight,
                                    size: 14,
                                  ),
                                  onPressed: widget.enabled && !_busy
                                      ? _settings
                                      : null,
                                  child: Text(
                                    'Open settings',
                                    style: AppTypography.bodySmall.copyWith(
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _step(
                          '2',
                          'Come back and reconnect',
                          'Keep your Ledger unlocked, then select “Find my Ledger” below.',
                          null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _error!,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        if (_stage == _Stage.devices || _stage == _Stage.scanning)
          ..._devices.map(
            (device) => Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: context.colors.background.neutralSubtleOpacity,
                  ),
                ),
              ),
              child: AppButton(
                expand: true,
                constrainContent: true,
                variant: AppButtonVariant.ghost,
                height: 56,
                contentPadding: EdgeInsets.zero,
                onPressed: widget.enabled && !_invalidated
                    ? () => _select(device)
                    : null,
                child: Row(
                  children: [
                    const AppIcon(AppIcons.ledger, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(device.name)),
                    const AppIcon(AppIcons.chevronForward, size: 16),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          expand: true,
          constrainContent: true,
          size: AppButtonSize.large,
          onPressed: _busy || !widget.enabled || _invalidated
              ? null
              : _stage == _Stage.ready
              ? () {
                  try {
                    _check(_generation);
                    widget.onRetry?.call();
                  } catch (error) {
                    _fail(_generation, error);
                  }
                }
              : _scan,
          child: Text(switch (_stage) {
            _Stage.scanning => 'Searching',
            _Stage.verifying => 'Checking account',
            _Stage.saving => 'Saving',
            _Stage.ready => 'Continue signing',
            _Stage.mismatch => 'Choose another Ledger',
            _Stage.devices => 'Search again',
            _ => 'Find my Ledger',
          }),
        ),
      ],
    );
  }

  Widget _step(String number, String title, String body, Widget? action) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: context.colors.background.neutralSubtleOpacity,
          ),
        ),
        child: Text(
          number,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              body,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            ?action,
          ],
        ),
      ),
    ],
  );
}
