import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../ledger_capability.dart';
import '../services/ledger_app_readiness_service.dart';
import 'ledger_device_app_prompt.dart';

enum LedgerSigningModalPhase {
  preparing,
  awaitingDevice,
  saving,
  broadcasting,
  failed,
}

class LedgerSigningFailurePresentation {
  const LedgerSigningFailurePresentation({
    required this.title,
    required this.statusLabel,
    required this.message,
    required this.showDeviceAppPrompt,
    this.actionLabel,
  });

  final String title;
  final String statusLabel;
  final String message;
  final bool showDeviceAppPrompt;
  final String? actionLabel;
}

class LedgerSigningModal extends ConsumerWidget {
  const LedgerSigningModal({
    required this.phase,
    required this.failure,
    required this.onCancel,
    required this.onFailureAction,
    this.cancelLabel = 'Cancel',
    this.accountUuid,
    super.key,
  }) : assert(
         phase == LedgerSigningModalPhase.failed || failure == null,
         'Failure presentation is only valid for the failed phase.',
       ),
       assert(
         phase != LedgerSigningModalPhase.failed || failure != null,
         'The failed phase requires an explicit presentation.',
       );

  final LedgerSigningModalPhase phase;
  final LedgerSigningFailurePresentation? failure;
  final VoidCallback? onCancel;
  final VoidCallback? onFailureAction;
  final String cancelLabel;
  final String? accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final networkName = ref.watch(
      rpcEndpointProvider.select((endpoint) => endpoint.networkName),
    );
    final appName = ledgerZcashAppName(networkName);
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    final account = _ledgerAccount(ref, accountUuid);
    final failed = phase == LedgerSigningModalPhase.failed;
    final failure = this.failure;
    var title = switch (phase) {
      LedgerSigningModalPhase.preparing => 'Preparing for Ledger',
      LedgerSigningModalPhase.awaitingDevice => 'Review on your Ledger',
      LedgerSigningModalPhase.saving => 'Saving signed transaction',
      LedgerSigningModalPhase.broadcasting => 'Sending transaction',
      LedgerSigningModalPhase.failed => failure!.title,
    };
    var message = switch (phase) {
      LedgerSigningModalPhase.preparing =>
        'Vizor is preparing the transaction for secure device review.',
      LedgerSigningModalPhase.awaitingDevice =>
        'Review every transaction detail on the device, then approve or reject it.',
      LedgerSigningModalPhase.saving =>
        'Keep Vizor open while the signed transaction is saved securely.',
      LedgerSigningModalPhase.broadcasting =>
        'Keep Vizor open while the transaction is sent.',
      LedgerSigningModalPhase.failed => failure!.message,
    };

    var statusLabel = switch (phase) {
      LedgerSigningModalPhase.preparing => 'Preparing transaction',
      LedgerSigningModalPhase.awaitingDevice => 'Waiting for approval',
      LedgerSigningModalPhase.saving => 'Securing transaction',
      LedgerSigningModalPhase.broadcasting => 'Broadcasting to the network',
      LedgerSigningModalPhase.failed => failure!.statusLabel,
    };
    if (phase == LedgerSigningModalPhase.failed &&
        readiness.phase == LedgerAppReadinessPhase.failed) {
      title = 'Ledger needs attention';
      statusLabel = 'Action needed';
      message = readiness.message!;
    }
    if (phase == LedgerSigningModalPhase.awaitingDevice) {
      switch (readiness.phase) {
        case LedgerAppReadinessPhase.checkingDevice:
          title = 'Checking your Ledger';
          statusLabel = 'Checking device';
          message = 'Vizor is checking whether the Zcash app is ready.';
        case LedgerAppReadinessPhase.confirmOpening:
          title = 'Confirm opening Zcash';
          statusLabel = 'Opening Zcash';
          message =
              'Confirm the request on your Ledger. Vizor will reconnect automatically.';
        case LedgerAppReadinessPhase.idle ||
            LedgerAppReadinessPhase.ready ||
            LedgerAppReadinessPhase.failed:
          break;
      }
    }
    final actionLabel = failed
        ? failure!.actionLabel
        : phase == LedgerSigningModalPhase.saving
        ? 'Saving'
        : 'Waiting';
    final showDeviceAppPrompt = switch (phase) {
      LedgerSigningModalPhase.saving ||
      LedgerSigningModalPhase.broadcasting => false,
      LedgerSigningModalPhase.failed => failure!.showDeviceAppPrompt,
      LedgerSigningModalPhase.preparing ||
      LedgerSigningModalPhase.awaitingDevice => true,
    };

    return AppModalCard(
      width: 328,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(color: colors.border.subtle),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.ledger,
                    size: 22,
                    color: colors.icon.regular,
                    semanticLabel: 'Ledger',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '$appName · Ledger',
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showDeviceAppPrompt) ...[
            const SizedBox(height: AppSpacing.md),
            LedgerDeviceAppPrompt(networkName: networkName),
          ],
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.background.neutralSubtleOpacity,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: AppIcon(
                      failed ? AppIcons.warningCircle : AppIcons.loader,
                      size: failed ? 24 : 20,
                      color: failed
                          ? colors.icon.destructive
                          : colors.icon.regular,
                      animated: !failed,
                      semanticLabel: statusLabel,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: AppTypography.bodyMedium.copyWith(
                          color: failed
                              ? colors.text.destructive
                              : colors.text.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        message,
                        style: AppTypography.bodySmall.copyWith(
                          color: failed
                              ? colors.text.destructive
                              : colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (failed &&
              account != null &&
              ref.watch(ledgerTargetPlatformProvider) ==
                  TargetPlatform.macOS) ...[
            const SizedBox(height: AppSpacing.sm),
            _LedgerFailureConnectionPicker(account: account),
          ],
          const SizedBox(height: AppSpacing.md),
          if (actionLabel == null && onCancel == null)
            const SizedBox.shrink()
          else if (actionLabel == null)
            AppButton(
              onPressed: onCancel,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.mediumLarge,
              minWidth: 280,
              child: Text(cancelLabel),
            )
          else if (onCancel == null)
            AppButton(
              onPressed: failed ? onFailureAction : null,
              variant: AppButtonVariant.primary,
              size: AppButtonSize.mediumLarge,
              minWidth: 280,
              child: Text(actionLabel),
            )
          else
            AppModalActions(
              onCancel: onCancel,
              cancelLabel: cancelLabel,
              actionLabel: actionLabel,
              onAction: failed ? onFailureAction : null,
            ),
        ],
      ),
    );
  }

  static AccountInfo? _ledgerAccount(WidgetRef ref, String? uuid) {
    if (uuid == null) return null;
    final accounts = ref.watch(accountProvider).value?.accounts ?? const [];
    for (final account in accounts) {
      if (account.uuid == uuid && account.isLedger) return account;
    }
    return null;
  }
}

class _LedgerFailureConnectionPicker extends ConsumerWidget {
  const _LedgerFailureConnectionPicker({required this.account});

  final AccountInfo account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bluetoothAvailable =
        account.ledgerDeviceId != null &&
        ledgerBluetoothTransportCapabilityForModel(
              model: account.ledgerDeviceModel,
              platform: ref.watch(ledgerTargetPlatformProvider),
            ) !=
            LedgerBluetoothCapability.unsupported;
    return Container(
      key: const ValueKey('ledger_failure_connection_picker'),
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Try another connection',
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (final option in LedgerConnectionPreference.values) ...[
                if (option != LedgerConnectionPreference.automatic)
                  const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: AppButton(
                    key: ValueKey('ledger_connection_${option.name}'),
                    onPressed:
                        option == LedgerConnectionPreference.bluetooth &&
                            !bluetoothAvailable
                        ? null
                        : () => unawaited(
                            ref
                                .read(accountProvider.notifier)
                                .updateLedgerConnectionPreference(
                                  account.uuid,
                                  option,
                                ),
                          ),
                    variant: account.ledgerConnectionPreference == option
                        ? AppButtonVariant.primary
                        : AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    constrainContent: true,
                    child: Text(switch (option) {
                      LedgerConnectionPreference.automatic => 'Auto',
                      LedgerConnectionPreference.usb => 'USB',
                      LedgerConnectionPreference.bluetooth => 'Bluetooth',
                    }),
                  ),
                ),
              ],
            ],
          ),
          if (!bluetoothAvailable) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Set up Bluetooth from Account details before using it for signing.',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
