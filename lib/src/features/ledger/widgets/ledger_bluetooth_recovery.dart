import 'package:flutter/widgets.dart';

import 'ledger_progress_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../services/ledger_mobile_ble_service.dart';

import 'ledger_bluetooth_session.dart';

class LedgerBluetoothRecovery extends StatelessWidget {
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
  Widget build(BuildContext context) => LedgerBluetoothSession(
    service: service,
    onRetry: onRetry,
    onClose: onClose,
    onBusyChanged: onBusyChanged,
    retryLabel: retryLabel,
    enabled: enabled,
    builder: _buildContent,
  );
  Widget _buildContent(
    BuildContext context,
    LedgerBluetoothPresentation model,
  ) {
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
                model.title,
                style: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                model.message,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (model.busy)
          const LedgerProgressStatus(label: 'Checking Bluetooth access…')
        else
          AppButton(
            onPressed: model.onAction,
            expand: true,
            constrainContent: true,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            child: Text(model.label),
          ),
      ],
    );
  }
}
