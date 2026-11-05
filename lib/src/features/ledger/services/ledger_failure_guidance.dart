import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../../../core/l10n/l10n.dart' show AppLocalizations;
import '../ledger_capability.dart';
import '../ledger_error_codes.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_connection_service.dart';
import 'ledger_mobile_ble_service.dart';

/// The request a Ledger failure belongs to, for copy that names it.
enum LedgerRequestKind {
  send,
  swap,
  payment,
  shield,
  migration,
  voting,
  giftCard,
  viewingKey,
}

/// Device guidance travels with the caught error, never with a previous
/// attempt's global readiness state. Declines, cancellations, transport loss
/// and unknown transaction errors stay with the caller so storage, broadcast
/// and proposal recovery retain their own actions.
class LedgerFailureGuidance {
  const LedgerFailureGuidance(
    this.message, {
    this.showDeviceAppPrompt = false,
    this.bluetoothRecovery = false,
    this.pairingRecovery = false,
    this.pairingInvalid = false,
    this.retryable = true,
  });

  final bool bluetoothRecovery;
  final bool pairingRecovery;
  final bool pairingInvalid;
  final String message;
  final bool showDeviceAppPrompt;

  /// False when retrying the same request fails the same way on the device;
  /// the caller must build a new request instead of offering a retry.
  final bool retryable;
}

/// A USB export or signing session found a different app than readiness
/// verified. Keep this identical to `LEDGER_APP_CHANGED` in
/// `rust/src/wallet/ledger/mod.rs`.
const ledgerAppChangedError =
    'Your Ledger changed. Keep one Ledger connected and try again.'; // l10n-ignore: matches the Rust error; shown via ledgerChangedKeepOne

LedgerFailureGuidance? ledgerFailureGuidance(
  AppLocalizations l10n,
  Object error, {
  LedgerRequestKind requestKind = LedgerRequestKind.send,
}) {
  if (isLedgerMemoHashUnsupported(error)) {
    return LedgerFailureGuidance(l10n.ledgerFailureMsgMemoHashUnsupported);
  }
  if (isLedgerAppUpdateRequired(error)) {
    return LedgerFailureGuidance(
      l10n.ledgerFailureMsgAppUpdateRequired(kLedgerNu7AppVersion),
    );
  }
  if (isLedgerOrchardChangeUnsupported(error)) {
    return LedgerFailureGuidance(
      l10n.ledgerFailureMsgOrchardChange,
      retryable: false,
    );
  }
  if (error.toString().contains(ledgerAppChangedError)) {
    return LedgerFailureGuidance(l10n.ledgerChangedKeepOne);
  }
  if (error is LedgerConnectionRequiredException) {
    return (error.cause == null
            ? null
            : ledgerFailureGuidance(
                l10n,
                error.cause!,
                requestKind: requestKind,
              )) ??
        LedgerFailureGuidance(switch (error.reason) {
          LedgerConnectionRequiredReason.bluetooth =>
            l10n.ledgerConnectionRequiredBluetooth,
          LedgerConnectionRequiredReason.usb =>
            l10n.ledgerConnectionRequiredUsb,
        });
  }
  if (error is LedgerAppReadinessException) {
    final cause = error.cause;
    return (cause == null
            ? null
            : ledgerFailureGuidance(l10n, cause, requestKind: requestKind)) ??
        LedgerFailureGuidance(_readinessMessage(l10n, error));
  }
  if (error is LedgerMobileException) return _mobileGuidance(l10n, error);

  final failure = LedgerRequestFailure.fromError(error);
  return switch (failure) {
    LedgerRequestFailure.requestRejected ||
    LedgerRequestFailure.requestTooLarge => LedgerFailureGuidance(
      _rebuildMessage(l10n, error, requestKind),
      retryable: false,
    ),
    // Only a running other app is fixed by opening Zcash; install and update
    // failures need Ledger Wallet, so the open-app card would contradict them.
    LedgerRequestFailure.wrongApp => LedgerFailureGuidance(
      failure.message(l10n),
      showDeviceAppPrompt: true,
    ),
    LedgerRequestFailure.appNotInstalled ||
    LedgerRequestFailure.appUpdateRequired => LedgerFailureGuidance(
      failure.message(l10n),
    ),
    LedgerRequestFailure.unexpectedStatus => LedgerFailureGuidance(
      _unexpectedStatusMessage(l10n, error),
    ),
    LedgerRequestFailure.deviceLocked ||
    LedgerRequestFailure.pinNotSet ||
    LedgerRequestFailure.appWrongState ||
    LedgerRequestFailure.busy ||
    LedgerRequestFailure.signatureMismatch => LedgerFailureGuidance(
      failure.message(l10n),
    ),
    LedgerRequestFailure.declined ||
    LedgerRequestFailure.cancelled ||
    LedgerRequestFailure.transportLost ||
    LedgerRequestFailure.other => null,
  };
}

/// Display text for a readiness failure whose cause carried no guidance. The
/// exception's own text stays English for logs and matching.
String _readinessMessage(
  AppLocalizations l10n,
  LedgerAppReadinessException error,
) {
  final cause = error.cause;
  if (cause != null && cause is! LedgerMobileException) {
    return switch (classifyLedgerError(cause)) {
      LedgerFailureKind.usbPermission => l10n.ledgerReadinessUsbPermission,
      LedgerFailureKind.userRejected => l10n.ledgerMobileRequestRejected,
      LedgerFailureKind.cancelled => l10n.ledgerReadinessOperationCancelled,
      LedgerFailureKind.transportLost =>
        l10n.ledgerReadinessReconnectUnlockTryAgain,
      _ => l10n.ledgerReadinessCouldNotPrepare,
    };
  }
  switch (error.reason) {
    case LedgerAppReadinessReason.appNotVerified:
      return l10n.ledgerReadinessAppNotVerified;
    case LedgerAppReadinessReason.openZcashApp:
      return l10n.ledgerReadinessOpenZcashApp;
    case LedgerAppReadinessReason.updateRequired:
      return l10n.ledgerReadinessUpdateApp(error.requiredVersion ?? '');
    case null:
      break;
  }
  return switch (error.failure) {
    LedgerAppReadinessFailure.locked => l10n.ledgerFailureMsgUnlock,
    LedgerAppReadinessFailure.disconnected =>
      l10n.ledgerReadinessReconnectUnlockTryAgain,
    _ => error.message, // l10n-ignore: exception text from readiness checks
  };
}

LedgerFailureGuidance _mobileGuidance(
  AppLocalizations l10n,
  LedgerMobileException error,
) => switch (error.failure) {
  LedgerMobileFailure.permissionDenied => LedgerFailureGuidance(
    l10n.ledgerMobileCheckBluetoothBelow,
    bluetoothRecovery: true,
  ),
  LedgerMobileFailure.locationDisabled => LedgerFailureGuidance(
    l10n.ledgerMobileTurnOnLocation,
    bluetoothRecovery: true,
  ),
  LedgerMobileFailure.bluetoothOff => LedgerFailureGuidance(
    l10n.ledgerMobileTurnOnBluetooth,
    bluetoothRecovery: true,
  ),
  LedgerMobileFailure.pairingInvalid => LedgerFailureGuidance(
    l10n.ledgerMobilePairingInvalid,
    pairingInvalid: true,
    pairingRecovery: true,
  ),
  LedgerMobileFailure.pairingRejected => LedgerFailureGuidance(
    l10n.ledgerMobilePairingNotCompleted,
    pairingRecovery: true,
  ),
  LedgerMobileFailure.disconnected => LedgerFailureGuidance(
    l10n.ledgerMobileConnectionLost,
    pairingRecovery: true,
  ),
  LedgerMobileFailure.busy => LedgerFailureGuidance(
    l10n.ledgerMobileAnotherRequestActive,
  ),
  LedgerMobileFailure.locked => LedgerFailureGuidance(
    l10n.ledgerFailureMsgUnlock,
  ),
  LedgerMobileFailure.rejected => LedgerFailureGuidance(
    l10n.ledgerMobileRequestRejected,
  ),
  LedgerMobileFailure.cancelled => LedgerFailureGuidance(
    l10n.ledgerMobileRequestCancelled,
  ),
  LedgerMobileFailure.wrongApp => LedgerFailureGuidance(
    l10n.ledgerFailureMsgOpenZcash,
    showDeviceAppPrompt: true,
  ),
  // Native unavailable messages can include instructions to finish a
  // pending device request. Preserve those instead of inventing a pairing
  // diagnosis.
  LedgerMobileFailure.unavailable => LedgerFailureGuidance(
    error.platformText
        ? error
              .message // l10n-ignore: platform text, wording unknown
        : l10n.ledgerMobileUnavailable,
  ),
};

/// How a failed Ledger request is presented, derived from the stable codes
/// [classifyLedgerError] reads. Pairing evidence and Bluetooth access
/// recovery remain separate from this presentation.
enum LedgerRequestFailure {
  declined,

  /// The app refused or could not parse a request Vizor built. Sending the
  /// same request again fails the same way.
  requestRejected,

  /// The request exceeds what the device can sign or hold in memory. Sending
  /// the same request again fails the same way.
  requestTooLarge,
  deviceLocked,
  pinNotSet,
  wrongApp,
  appNotInstalled,
  appUpdateRequired,
  appWrongState,
  busy,
  cancelled,
  transportLost,
  signatureMismatch,
  unexpectedStatus,
  other;

  static LedgerRequestFailure fromError(Object error) =>
      switch (classifyLedgerError(error)) {
        LedgerFailureKind.userRejected => declined,
        LedgerFailureKind.hostRequestRejected => requestRejected,
        LedgerFailureKind.capacityExceeded => requestTooLarge,
        LedgerFailureKind.deviceLocked => deviceLocked,
        LedgerFailureKind.pinNotSet => pinNotSet,
        LedgerFailureKind.wrongApp => wrongApp,
        LedgerFailureKind.appNotInstalled => appNotInstalled,
        LedgerFailureKind.appUpdateRequired => appUpdateRequired,
        LedgerFailureKind.appWrongState => appWrongState,
        LedgerFailureKind.deviceBusy => busy,
        LedgerFailureKind.cancelled => cancelled,
        LedgerFailureKind.transportLost ||
        LedgerFailureKind.usbPermission => transportLost,
        LedgerFailureKind.signatureMismatch => signatureMismatch,
        LedgerFailureKind.deviceInternalError ||
        LedgerFailureKind.unknownStatus => unexpectedStatus,
        LedgerFailureKind.saplingUnsupported || LedgerFailureKind.other =>
          _exceedsTransactionFormat(error) ? requestRejected : other,
      };

  /// Whether sending the same request again can succeed.
  bool get retryable => this != requestRejected && this != requestTooLarge;

  String title(AppLocalizations l10n) => switch (this) {
    declined => l10n.ledgerSheetDeclinedTitle,
    requestRejected => l10n.ledgerFailureTitleRejected,
    requestTooLarge => l10n.ledgerFailureTitleTooLarge,
    deviceLocked => l10n.ledgerFailureTitleLocked,
    pinNotSet => l10n.ledgerFailureTitlePinRequired,
    wrongApp => l10n.ledgerFailureTitleOpenZcash,
    appNotInstalled => l10n.ledgerFailureTitleZcashMissing,
    appUpdateRequired => l10n.ledgerFailureTitleUpdateZcash,
    appWrongState => l10n.ledgerFailureTitleReopenZcash,
    busy => l10n.ledgerFailureTitleBusy,
    cancelled => l10n.ledgerFailureTitleCancelled,
    transportLost => l10n.ledgerFailureTitleNotReachable,
    signatureMismatch => l10n.ledgerFailureTitleWrongLedger,
    unexpectedStatus => l10n.ledgerFailureTitleError,
    other => l10n.ledgerFailureTitleFailed,
  };

  String message(AppLocalizations l10n) => switch (this) {
    declined => l10n.ledgerFailureMsgDeclined,
    requestRejected => l10n.ledgerFailureMsgRejectedNewRequest,
    requestTooLarge => l10n.ledgerFailureMsgTooManyInputs,
    deviceLocked => l10n.ledgerFailureMsgUnlock,
    pinNotSet => l10n.ledgerFailureMsgSetPin,
    wrongApp => l10n.ledgerFailureMsgOpenZcash,
    appNotInstalled => l10n.ledgerFailureMsgInstallZcash,
    appUpdateRequired => l10n.ledgerFailureMsgUpdateZcash(
      kMinimumLedgerZcashAppVersion,
    ),
    appWrongState => l10n.ledgerFailureMsgReopenZcash,
    busy => l10n.ledgerFailureMsgBusy,
    cancelled => l10n.ledgerFailureMsgCancelledTryAgain,
    transportLost => l10n.ledgerFailureMsgReconnectUnlock,
    signatureMismatch => l10n.ledgerFailureMsgWrongLedger,
    unexpectedStatus => l10n.ledgerFailureMsgUnexpected,
    other => l10n.ledgerFailureMsgCheckOpenZcash,
  };
}

// Rust rejects a transparent output with several BIP-32 derivations before
// any device exchange; its wallet-built message is the only evidence.
bool _exceedsTransactionFormat(Object error) =>
    error.toString().toLowerCase().contains('ledger supports at most');

String _rebuildMessage(
  AppLocalizations l10n,
  Object error,
  LedgerRequestKind kind,
) {
  if (classifyLedgerError(error) == LedgerFailureKind.capacityExceeded) {
    return switch (kind) {
      LedgerRequestKind.send || LedgerRequestKind.viewingKey =>
        LedgerRequestFailure.requestTooLarge.message(l10n),
      LedgerRequestKind.swap => l10n.ledgerFailureMsgSwapTooLarge,
      LedgerRequestKind.payment => l10n.ledgerFailureMsgPaymentTooLarge,
      LedgerRequestKind.shield => l10n.ledgerFailureMsgShieldTooLarge,
      // The planner does not size steps by Ledger limits, and retrying sends
      // the same step.
      LedgerRequestKind.migration => l10n.ledgerFailureMsgMigrationTooLarge,
      // The round's bundle policy fixes the vote's size.
      LedgerRequestKind.voting => l10n.ledgerFailureMsgVoteTooLarge,
      LedgerRequestKind.giftCard => l10n.ledgerFailureMsgGiftCardTooLarge,
    };
  }
  if (_exceedsTransactionFormat(error)) {
    return l10n.ledgerFailureMsgUnsupportedTxType;
  }
  return switch (kind) {
    LedgerRequestKind.voting => l10n.ledgerFailureMsgVoteRejected,
    LedgerRequestKind.giftCard => l10n.ledgerFailureMsgGiftCardRejected,
    LedgerRequestKind.viewingKey => l10n.ledgerFailureMsgViewingKeyRejected,
    _ => l10n.ledgerFailureMsgRejectedNewRequest,
  };
}

String _unexpectedStatusMessage(AppLocalizations l10n, Object error) {
  final status = ledgerStatusWord(error);
  final code = status == null
      ? ''
      : ' (0x${status.toRadixString(16).padLeft(4, '0')})';
  return l10n.ledgerFailureMsgUnexpectedWithCode(code);
}

String ledgerUsbPermissionMessage(
  AppLocalizations l10n,
  TargetPlatform platform,
) {
  // Linux hidraw nodes stay root-only until a udev rule grants access.
  return platform == TargetPlatform.linux
      ? l10n.ledgerUsbPermissionLinux
      : l10n.ledgerUsbPermissionOther;
}

/// Tells the Rust USB transport's failures apart, so "no Ledger plugged in"
/// never reads as "Vizor cannot open the Ledger" or as a device rejection.
String? ledgerUsbErrorMessage(
  AppLocalizations l10n,
  Object error, {
  required String appInstruction,
  TargetPlatform? platform,
}) {
  if (!isLedgerUsbTransportError(error)) return null;
  final text = error.toString().toLowerCase();
  if (text.contains('no ledger device')) {
    return l10n.ledgerErrorConnectAndUnlock(appInstruction);
  }
  if (text.contains('open ledger hid device')) {
    if (text.contains('permission denied') ||
        text.contains('access is denied') ||
        text.contains('access denied')) {
      return ledgerUsbPermissionMessage(
        l10n,
        platform ?? defaultTargetPlatform,
      );
    }
    return l10n.ledgerUsbCouldNotOpen;
  }
  if (text.contains('initialize ledger hid')) {
    return l10n.ledgerUsbCouldNotStart;
  }
  return l10n.ledgerUsbInterrupted(appInstruction);
}
