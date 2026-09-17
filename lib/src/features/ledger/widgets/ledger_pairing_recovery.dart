import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ledger_device_label.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../ledger_capability.dart';
import '../services/ledger_bluetooth_access.dart';
import '../services/ledger_device_selection.dart';
import '../services/ledger_pairing_recovery_service.dart';
import 'ledger_bluetooth_recovery.dart';
import 'ledger_progress_status.dart';

import 'ledger_pairing_session.dart';

class LedgerPairingRecovery extends ConsumerWidget {
  const LedgerPairingRecovery({
    required this.accountUuid,
    required this.onRetry,
    required this.onClose,
    required this.onBusyChanged,
    this.enabled = true,
    this.pairingInvalid = false,
    this.selectionRequest,
    this.retrySelectsDevice = false,
    super.key,
  });
  final String accountUuid;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;
  final bool pairingInvalid;
  final LedgerDeviceSelectionRequest? selectionRequest;
  final bool retrySelectsDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LedgerPairingSession(
    accountUuid: accountUuid,
    pairingInvalid: pairingInvalid,
    onRetry: onRetry,
    onClose: onClose,
    onBusyChanged: onBusyChanged,
    enabled: enabled,
    selectionRequest: selectionRequest,
    retrySelectsDevice: retrySelectsDevice,
    builder: (context, session) => _buildContent(context, ref, session),
  );

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    LedgerPairingSessionState c,
  ) {
    if (c.accessRecovery) {
      return LedgerBluetoothRecovery(
        service: c.service,
        onRetry: c.scan,
        onClose: onClose,
        retryLabel: 'Find my Ledger',
        enabled: enabled,
        onBusyChanged: onBusyChanged,
      );
    }
    final savedId = ref
        .watch(accountProvider)
        .value
        ?.accounts
        .where((account) => account.uuid == accountUuid)
        .firstOrNull
        ?.ledgerDeviceId;
    final platform = ref.watch(ledgerTargetPlatformProvider);
    final settingsLink =
        platform != TargetPlatform.iOS &&
        c.service is LedgerBluetoothPairingSettings;
    final title = switch (c.stage) {
      LedgerPairingStage.failed =>
        c.pairingInvalid ? 'Pair your Ledger again' : c.requestFailure.title,
      LedgerPairingStage.scanning || LedgerPairingStage.devices =>
        c.devices.isEmpty
            ? (c.stage == LedgerPairingStage.scanning
                  ? 'Finding your Ledger'
                  : 'No Ledger devices found')
            : 'Select your Ledger',
      LedgerPairingStage.verifying =>
        c.sameSavedDevice ? 'Connecting to your Ledger' : 'Check your Ledger',
      LedgerPairingStage.saving => 'Saving your connection',
      LedgerPairingStage.ready => 'Your Ledger is connected',
      LedgerPairingStage.mismatch => 'This Ledger doesn’t match',
    };
    final message = switch (c.stage) {
      LedgerPairingStage.failed =>
        c.pairingInvalid
            ? 'Your Ledger no longer recognizes this Bluetooth pairing. Remove the old pairing, then reconnect.'
            : c.requestFailure.message,
      LedgerPairingStage.scanning || LedgerPairingStage.devices =>
        c.devices.isEmpty
            ? 'Keep your Ledger nearby and unlocked.'
            : 'Choose the Ledger you want to use for this account.',
      LedgerPairingStage.verifying =>
        c.sameSavedDevice
            ? 'Unlock your Ledger and open the Zcash app. Approve opening it if prompted.'
            : 'Complete pairing if prompted, then open the Zcash app and approve sharing the viewing key.',
      LedgerPairingStage.saving =>
        'Your account matches. Saving the verified connection.',
      LedgerPairingStage.ready =>
        c.connectionUpdated
            ? 'This Ledger matches your account. Your saved connection has been updated.'
            : c.sameSavedDevice
            ? 'Continue when you’re ready to review the transaction on your Ledger.'
            : 'Account verified. Continue when you’re ready to review the transaction on your Ledger.',
      LedgerPairingStage.mismatch =>
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
        if (c.stage == LedgerPairingStage.failed &&
            !c.pairingInvalid &&
            c.selectedDevice != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppIcon(
                AppIcons.ledger,
                size: 20,
                color: context.colors.icon.regular,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  ledgerDeviceLabel(c.selectedDevice!),
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (c.stage == LedgerPairingStage.failed && c.pairingInvalid) ...[
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
                Padding(
                  padding: EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      _step(
                        context,
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
                                onPressed: enabled && !c.busy
                                    ? c.settings
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
                        context,
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
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              c.error!,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        if (c.stage == LedgerPairingStage.devices ||
            c.stage == LedgerPairingStage.scanning)
          ...c.devices.map(
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
                height: 64,
                growWithContent: true,
                contentPadding: EdgeInsets.zero,
                onPressed: enabled && !c.invalidated
                    ? () => c.select(device)
                    : null,
                child: Row(
                  children: [
                    const AppIcon(AppIcons.ledger, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ledgerDeviceLabel(device)),
                          if (ledgerDeviceDiffersFromSavedConnection(
                            savedId,
                            device.id,
                          )) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Different from saved connection',
                              style: AppTypography.bodySmall.copyWith(
                                color: context.colors.text.secondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const AppIcon(AppIcons.chevronForward, size: 16),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (c.busy)
          LedgerProgressStatus(
            label: switch (c.stage) {
              LedgerPairingStage.scanning =>
                c.devices.isEmpty
                    ? 'Searching nearby…'
                    : 'Still searching nearby…',
              LedgerPairingStage.verifying =>
                c.sameSavedDevice
                    ? 'Connecting…'
                    : 'Follow the prompts on your Ledger',
              LedgerPairingStage.saving => 'Saving connection…',
              _ => 'Opening Bluetooth settings…',
            },
          )
        else
          AppButton(
            expand: true,
            constrainContent: true,
            size: AppButtonSize.large,
            onPressed: c.busy || !enabled || c.invalidated
                ? null
                : c.stage == LedgerPairingStage.ready
                ? c.continueSigning
                : c.scan,
            child: Text(switch (c.stage) {
              LedgerPairingStage.scanning => 'Searching',
              LedgerPairingStage.verifying =>
                c.sameSavedDevice ? 'Connecting' : 'Checking account',
              LedgerPairingStage.saving => 'Saving',
              LedgerPairingStage.ready => 'Continue signing',
              LedgerPairingStage.mismatch => 'Choose another Ledger',
              LedgerPairingStage.devices => 'Search again',
              LedgerPairingStage.failed when !c.pairingInvalid => 'Try again',
              _ => 'Find my Ledger',
            }),
          ),
      ],
    );
  }

  Widget _step(
    BuildContext context,
    String number,
    String title,
    String body,
    Widget? action,
  ) => Row(
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
