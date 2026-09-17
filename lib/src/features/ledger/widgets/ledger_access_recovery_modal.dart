import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../providers/account_provider.dart';
import '../ledger_capability.dart';
import '../services/ledger_device_request.dart';
import 'ledger_bluetooth_recovery.dart';
import 'ledger_pairing_recovery.dart';

/// A connection recovery surface, never used for saved/broadcast transactions.
class LedgerAccessRecoveryModal extends ConsumerStatefulWidget {
  const LedgerAccessRecoveryModal({
    required this.account,
    required this.onRetry,
    required this.onClose,
    this.pairingRecovery = false,
    super.key,
  });
  final AccountInfo? account;
  final bool pairingRecovery;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  @override
  ConsumerState<LedgerAccessRecoveryModal> createState() =>
      _LedgerAccessRecoveryModalState();
}

class _LedgerAccessRecoveryModalState
    extends ConsumerState<LedgerAccessRecoveryModal> {
  bool _usb = false;
  bool _saving = false;
  bool _accessBusy = false;
  String? _error;

  Future<void> _select(bool usb) async {
    if (_saving || _accessBusy || _usb == usb) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final check = ref.read(ledgerDeviceRequestsProvider).capture();
      await ref
          .read(accountProvider.notifier)
          .updateLedgerConnectionPreference(
            widget.account!.uuid,
            usb
                ? LedgerConnectionPreference.usb
                : LedgerConnectionPreference.bluetooth,
          );
      check();
      if (!mounted) return;
      setState(() => _usb = usb);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not change the connection. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(ledgerTargetPlatformProvider);
    final account = widget.account;
    final canChoose =
        platform == TargetPlatform.macOS &&
        account?.ledgerDeviceId != null &&
        ledgerBluetoothTransportCapabilityForModel(
              model: account?.ledgerDeviceModel,
              platform: platform,
            ) ==
            LedgerBluetoothCapability.supported;
    return AppModalCard(
      width: 328,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    canChoose ? 'Ledger' : 'Ledger · Bluetooth',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  AppButton(
                    onPressed: _saving ? null : widget.onClose,
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    child: const AppIcon(
                      AppIcons.cross,
                      size: 16,
                      semanticLabel: 'Close',
                    ),
                  ),
              ],
            ),
            if (canChoose) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Connection',
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: context.colors.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: Row(
                  children: [
                    for (final usb in [false, true]) ...[
                      if (usb) const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: AppButton(
                          key: ValueKey(
                            'ledger_recovery_${usb ? 'usb' : 'bluetooth'}',
                          ),
                          expand: true,
                          constrainContent: true,
                          size: AppButtonSize.medium,
                          onPressed: _saving || _accessBusy
                              ? null
                              : () => unawaited(_select(usb)),
                          variant: _usb == usb
                              ? AppButtonVariant.secondary
                              : AppButtonVariant.ghost,
                          child: Text(usb ? 'USB' : 'Bluetooth'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (_usb) ...[
              Text(
                'Connect your Ledger via USB',
                style: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Connect your Ledger with a USB cable and unlock it.',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                expand: true,
                constrainContent: true,
                onPressed: _saving ? null : widget.onRetry,
                size: AppButtonSize.large,
                child: const Text('Connect'),
              ),
            ] else if (widget.pairingRecovery && account != null)
              LedgerPairingRecovery(
                accountUuid: account.uuid,
                onRetry: widget.onRetry,
                onClose: widget.onClose,
                enabled: !_saving,
                onBusyChanged: (busy) {
                  _accessBusy = busy;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                },
              )
            else
              LedgerBluetoothRecovery(
                enabled: !_saving,
                onRetry: _saving ? null : widget.onRetry,
                onClose: widget.onClose,
                onBusyChanged: (busy) {
                  _accessBusy = busy;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}
