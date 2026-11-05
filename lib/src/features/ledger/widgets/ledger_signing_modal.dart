import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import 'mobile/mobile_ledger_signing_content.dart';
import 'desktop_ledger_signing_content.dart';
import '../ledger_device_label.dart';

import 'package:flutter/widgets.dart';

import 'ledger_access_recovery_modal.dart';
import '../services/ledger_device_selection.dart';
import '../services/ledger_mobile_ble_service.dart';
import '../services/ledger_bluetooth_access.dart';
import '../../../core/navigation/external_action_guard_hold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../ledger_capability.dart';
import '../services/ledger_app_readiness_service.dart';
import '../services/ledger_signing_progress.dart';
import '../services/ledger_failure_guidance.dart';

enum LedgerSigningModalPhase {
  preparing,
  awaitingDevice,
  finishing,
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
    this.showConnectionPicker = true,
    this.bluetoothRecovery = false,
    this.pairingRecovery = false,
    this.pairingInvalid = false,
    this.requestFailure,
  });

  final String title;
  final String statusLabel;
  final String message;
  final bool showDeviceAppPrompt;
  final String? actionLabel;
  final bool isError;
  final bool showConnectionPicker;
  final bool bluetoothRecovery;
  final bool pairingRecovery;
  final bool pairingInvalid;
  final LedgerRequestFailure? requestFailure;
}

/// A memo the connected app would show as a hash was refused because the app
/// predates [kLedgerMemoHashAppVersion]. Retrying after an update reads the new
/// version, so the action stays a retry.
LedgerSigningFailurePresentation ledgerMemoHashUpdateFailure(
  AppLocalizations l10n,
) => LedgerSigningFailurePresentation(
  title: l10n.ledgerAppUpdateRequiredTitle,
  statusLabel: l10n.commonActionNeeded,
  message: l10n.ledgerFailureMsgMemoHashUnsupported,
  showDeviceAppPrompt: false,
  actionLabel: l10n.commonTryAgain,
);

/// An NU7 or Orchard-to-Ironwood transaction was refused because the app
/// predates [kLedgerNu7AppVersion]; retrying after an update reads the new
/// version.
LedgerSigningFailurePresentation ledgerAppUpdateFailure(
  AppLocalizations l10n,
) => LedgerSigningFailurePresentation(
  title: l10n.ledgerAppUpdateRequiredTitle,
  statusLabel: l10n.commonActionNeeded,
  message: l10n.ledgerFailureMsgAppUpdateRequired(kLedgerNu7AppVersion),
  showDeviceAppPrompt: false,
  actionLabel: l10n.commonTryAgain,
);

class LedgerSigningModal extends ConsumerWidget {
  const LedgerSigningModal({
    required this.phase,
    required this.failure,
    required this.onCancel,
    required this.onFailureAction,
    this.cancelLabel,
    this.accountUuid,
    this.connectionScope,
    this.signingStage,
    this.roundFeeNotice,
    this.roundNumber = 1,
    this.roundCount = 1,
    this.cancelling = false,
    this.resumingApproval = false,
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
  final String? cancelLabel;
  final String? accountUuid;
  final LedgerConnectionScope? connectionScope;
  final LedgerSigningStage? signingStage;
  final String? roundFeeNotice;
  final int roundNumber;
  final int roundCount;
  final bool cancelling;
  // Keep transaction preparation complete while retrying the Ledger request.
  final bool resumingApproval;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ExternalActionGuardHold(child: _buildContent(context, ref));

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    final account = _ledgerAccount(ref, accountUuid);
    final selection = ref.watch(ledgerDeviceSelectionProvider);
    if (selection != null &&
        selection.accountUuid == accountUuid &&
        account != null) {
      return LedgerAccessRecoveryModal(
        key: ObjectKey(selection),
        account: account,
        selectionRequest: selection,
        onRetry: null,
        onClose: onCancel,
      );
    }
    final failed = phase == LedgerSigningModalPhase.failed;
    final failure = this.failure;
    final platform = ref.watch(ledgerTargetPlatformProvider);
    final canChangeConnection =
        failed &&
        failure!.showConnectionPicker &&
        onFailureAction != null &&
        connectionScope != null &&
        platform == TargetPlatform.macOS;
    void changeConnection() {
      connectionScope!.changeConnection();
      onFailureAction?.call();
    }

    if (failed &&
        (failure!.bluetoothRecovery ||
            (failure.pairingRecovery && account != null)) &&
        ref.watch(ledgerMobileBleServiceProvider) is LedgerBluetoothAccess) {
      return LedgerAccessRecoveryModal(
        key: ValueKey(accountUuid),
        account: account,
        pairingRecovery: failure.pairingRecovery,
        pairingInvalid: failure.pairingInvalid,
        retrySelectsDevice: true,
        onChangeConnection: canChangeConnection ? changeConnection : null,
        onRetry: onFailureAction,
        onClose: onCancel,
      );
    }
    final progress = ref.watch(ledgerSigningProgressProvider);
    final stage = switch (phase) {
      LedgerSigningModalPhase.preparing => LedgerSigningStage.preparing,
      LedgerSigningModalPhase.awaitingDevice =>
        signingStage ??
            (progress?.accountUuid == accountUuid ? progress?.stage : null) ??
            LedgerSigningStage.preparing,
      LedgerSigningModalPhase.finishing ||
      LedgerSigningModalPhase.saving ||
      LedgerSigningModalPhase.broadcasting => LedgerSigningStage.finishing,
      LedgerSigningModalPhase.failed => LedgerSigningStage.preparing,
    };
    var title = failed ? _failureTitle(l10n, failure!) : stage.title(l10n);
    var message = failed ? failure!.message : stage.message(l10n);
    var statusLabel = failed ? failure!.statusLabel : stage.status(l10n);
    if (phase == LedgerSigningModalPhase.finishing) {
      title = l10n.ledgerSigningTitleFinishing;
      message = l10n.ledgerSigningApprovedFinishing;
      statusLabel = l10n.ledgerSigningKeepVizorOpenShort;
    }
    if (roundCount > 1) {
      final progress = l10n.ledgerSigningTransactionProgress(
        '$roundNumber',
        '$roundCount',
      );
      if (!failed) statusLabel = progress;
    }
    if ((phase == LedgerSigningModalPhase.awaitingDevice ||
            phase == LedgerSigningModalPhase.preparing) &&
        stage == LedgerSigningStage.preparing) {
      switch (readiness.phase) {
        case LedgerAppReadinessPhase.checkingDevice:
          title = l10n.commonCheckingYourLedger;
          statusLabel = l10n.ledgerSigningStatusCheckingDevice;
          message = l10n.commonVizorIsCheckingWhetherTheZcash;
        case LedgerAppReadinessPhase.confirmOpening:
          title = l10n.commonConfirmOpeningZcash;
          statusLabel = l10n.ledgerSigningStatusOpeningZcash;
          message = l10n.ledgerSigningConfirmRequestReconnect;
        case LedgerAppReadinessPhase.idle ||
            LedgerAppReadinessPhase.ready ||
            LedgerAppReadinessPhase.failed:
          break;
      }
    }
    final actionLabel = failed ? failure!.actionLabel : null;

    if (kAppFormFactor == AppFormFactor.mobile) {
      return MobileLedgerSigningContent(
        title: !failed && stage == LedgerSigningStage.reviewing
            ? l10n.ledgerSigningTitleConfirmOnLedger
            : title,
        message: message,
        status:
            !failed && stage == LedgerSigningStage.reviewing && roundCount == 1
            ? l10n.ledgerSigningStatusWaitingApproval
            : statusLabel,
        active: !failed,
        failed: failed,
        account: account,
        onClose: onCancel,
        actionLabel: actionLabel,
        onAction: onFailureAction,
        stage: stage,
        readiness: readiness.phase,
        saving: phase == LedgerSigningModalPhase.saving,
        finishing: phase == LedgerSigningModalPhase.finishing,
        broadcasting: phase == LedgerSigningModalPhase.broadcasting,
        declined: failure?.requestFailure == LedgerRequestFailure.declined,
        roundNumber: roundNumber,
        roundCount: roundCount,
        roundFeeNotice: roundFeeNotice,
        cancelling: cancelling,
        resumingApproval: resumingApproval,
      );
    }
    final selected = connectionScope?.selected?.device;
    final model = progress?.accountUuid == accountUuid
        ? progress?.deviceModel
        : null;
    final bluetooth =
        ledgerSupportsBluetooth(platform) &&
        (connectionScope?.transport == LedgerConnectionTransport.bluetooth ||
            (connectionScope?.transport == null &&
                account?.ledgerDeviceId != null));
    final identity = selected != null
        ? ledgerDeviceLabel(selected)
        : account?.ledgerDeviceName ??
              model ??
              'Ledger'; // l10n-ignore: product name
    return DesktopLedgerSigningContent(
      stage: stage,
      readiness: readiness.phase,
      message: message,
      failed: failed,
      declined: failure?.requestFailure == LedgerRequestFailure.declined,
      saving: phase == LedgerSigningModalPhase.saving,
      finishing: phase == LedgerSigningModalPhase.finishing,
      broadcasting: phase == LedgerSigningModalPhase.broadcasting,
      cancelling: cancelling,
      preparationComplete:
          resumingApproval || phase == LedgerSigningModalPhase.awaitingDevice,
      failureTitle: title,
      onCancel: onCancel,
      onAction: onFailureAction,
      actionLabel: actionLabel,
      cancelLabel: cancelLabel,
      onChangeConnection: canChangeConnection ? changeConnection : null,
      identity:
          '$identity · ${bluetooth ? l10n.ledgerTransportBluetooth : l10n.ledgerTransportUsb}',
      roundNumber: roundNumber,
      roundCount: roundCount,
      roundFeeNotice: roundFeeNotice,
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

// Every flow names a required app update the same way.
String _failureTitle(
  AppLocalizations l10n,
  LedgerSigningFailurePresentation failure,
) => failure.requestFailure == LedgerRequestFailure.appUpdateRequired
    ? l10n.ledgerAppUpdateRequiredTitle
    : failure.title;
