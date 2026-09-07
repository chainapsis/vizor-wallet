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
  connecting,
  coolingDown,
  cancelling,
  reconnecting,
  cancelled,
  readyToRetry,
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
    this.isError = true,
  });

  final String title;
  final String statusLabel;
  final String message;
  final bool showDeviceAppPrompt;
  final String? actionLabel;
  final bool isError;
}

class LedgerSigningModal extends ConsumerWidget {
  const LedgerSigningModal({
    required this.phase,
    required this.failure,
    required this.onCancel,
    required this.onFailureAction,
    this.cancelLabel = 'Cancel',
    this.accountUuid,
    this.roundNumber = 1,
    this.roundCount = 1,
    this.showWaitingHint = false,
    super.key,
  }) : assert(roundNumber > 0 && roundNumber <= roundCount),
       assert(roundCount > 0),
       assert(
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
  final int roundNumber;
  final int roundCount;
  final bool showWaitingHint;

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
    final destructive = failed && failure!.isError;
    final settling =
        phase == LedgerSigningModalPhase.cancelling ||
        phase == LedgerSigningModalPhase.reconnecting;
    var title = switch (phase) {
      LedgerSigningModalPhase.preparing => 'Preparing for Ledger',
      LedgerSigningModalPhase.connecting => 'Connecting to your Ledger',
      LedgerSigningModalPhase.coolingDown => 'Getting your Ledger ready',
      LedgerSigningModalPhase.cancelling => 'Finishing your request',
      LedgerSigningModalPhase.reconnecting => 'Reconnecting your Ledger',
      LedgerSigningModalPhase.cancelled => 'Request canceled',
      LedgerSigningModalPhase.readyToRetry => 'Your Ledger is connected',
      LedgerSigningModalPhase.awaitingDevice => 'Review on your Ledger',
      LedgerSigningModalPhase.saving => 'Saving signed transaction',
      LedgerSigningModalPhase.broadcasting => 'Sending transaction',
      LedgerSigningModalPhase.failed => failure!.title,
    };
    var message = switch (phase) {
      LedgerSigningModalPhase.preparing =>
        'Vizor is preparing the transaction for secure device review.',
      LedgerSigningModalPhase.connecting =>
        'Keep your Ledger connected and unlocked.',
      LedgerSigningModalPhase.coolingDown =>
        'This will only take a moment. Keep your Ledger connected.',
      LedgerSigningModalPhase.cancelling =>
        'Vizor is waiting for the previous device request to finish before you can try again.',
      LedgerSigningModalPhase.reconnecting =>
        'Keep your Ledger connected and unlocked. Reconnecting will not send a new signing request.',
      LedgerSigningModalPhase.cancelled =>
        'You can go back or try again when you’re ready.',
      LedgerSigningModalPhase.readyToRetry =>
        'Choose Try again when you’re ready to review the transaction on your Ledger.',
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
      LedgerSigningModalPhase.connecting => 'Connecting',
      LedgerSigningModalPhase.coolingDown => 'Getting ready',
      LedgerSigningModalPhase.cancelling => 'Finishing up',
      LedgerSigningModalPhase.reconnecting => 'Connecting',
      LedgerSigningModalPhase.cancelled => 'Ready when you are',
      LedgerSigningModalPhase.readyToRetry => 'Ready when you are',
      LedgerSigningModalPhase.awaitingDevice => 'Waiting for approval',
      LedgerSigningModalPhase.saving => 'Securing transaction',
      LedgerSigningModalPhase.broadcasting => 'Broadcasting to the network',
      LedgerSigningModalPhase.failed => failure!.statusLabel,
    };
    if (roundCount > 1) {
      final progress = 'Transaction $roundNumber of $roundCount';
      if (phase == LedgerSigningModalPhase.preparing) {
        title = 'Preparing $progress';
        statusLabel = progress;
      } else if (phase == LedgerSigningModalPhase.awaitingDevice) {
        title = 'Review $progress on your Ledger';
        statusLabel = 'Waiting for approval · $roundNumber of $roundCount';
        message =
            'Approve this transaction on the device. Vizor will request the next transaction separately.';
      } else if (phase == LedgerSigningModalPhase.saving) {
        statusLabel = 'Securing both signed transactions';
      }
    }
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
      LedgerSigningModalPhase.broadcasting ||
      LedgerSigningModalPhase.coolingDown ||
      LedgerSigningModalPhase.cancelling ||
      LedgerSigningModalPhase.readyToRetry ||
      LedgerSigningModalPhase.cancelled => false,
      LedgerSigningModalPhase.failed => failure!.showDeviceAppPrompt,
      LedgerSigningModalPhase.preparing ||
      LedgerSigningModalPhase.connecting ||
      LedgerSigningModalPhase.reconnecting ||
      LedgerSigningModalPhase.awaitingDevice => true,
    };

    return AppModalCard(
      width: 328,
      child: SingleChildScrollView(
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
                        failed
                            ? AppIcons.warningCircle
                            : phase == LedgerSigningModalPhase.cancelled ||
                                  phase == LedgerSigningModalPhase.readyToRetry
                            ? AppIcons.checkCircle
                            : AppIcons.loader,
                        size: failed ? 24 : 20,
                        color: destructive
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
                            color: destructive
                                ? colors.text.destructive
                                : colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          message,
                          style: AppTypography.bodySmall.copyWith(
                            color: destructive
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
            if (showWaitingHint &&
                phase == LedgerSigningModalPhase.awaitingDevice &&
                readiness.phase == LedgerAppReadinessPhase.ready) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No request on your Ledger? Make sure it’s unlocked and the $appName app is open.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (settling)
              AppButton(
                onPressed: null,
                variant: AppButtonVariant.primary,
                size: AppButtonSize.mediumLarge,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      phase == LedgerSigningModalPhase.cancelling
                          ? 'Finishing up'
                          : 'Reconnecting',
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const AppIcon(AppIcons.loader, size: 16),
                  ],
                ),
              )
            else if (phase == LedgerSigningModalPhase.cancelled ||
                phase == LedgerSigningModalPhase.readyToRetry)
              AppModalActions(
                onCancel: onFailureAction,
                cancelLabel: 'Try again',
                actionLabel: 'Back',
                onAction: onCancel,
              )
            else if (actionLabel == null && onCancel == null)
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in LedgerConnectionPreference.values) ...[
                if (option != LedgerConnectionPreference.automatic)
                  const SizedBox(height: AppSpacing.xxs),
                Semantics(
                  selected: account.ledgerConnectionPreference == option,
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
                    size: AppButtonSize.medium,
                    constrainContent: true,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(switch (option) {
                            LedgerConnectionPreference.automatic => 'Auto',
                            LedgerConnectionPreference.usb => 'USB',
                            LedgerConnectionPreference.bluetooth => 'Bluetooth',
                          }),
                        ),
                        if (account.ledgerConnectionPreference == option)
                          AppIcon(
                            AppIcons.check,
                            key: ValueKey(
                              'ledger_connection_selected_${option.name}',
                            ),
                            size: 16,
                          )
                        else
                          const SizedBox(width: 16),
                      ],
                    ),
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
