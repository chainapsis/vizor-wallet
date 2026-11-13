import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;

import '../../../core/l10n/l10n.dart';
import '../../../core/zcash/broadcast_notice_text.dart';
import '../../../rust/api/sync.dart' show BroadcastNotice;

// Enum names below are written into persisted swap records
// (`statusErrorCode`, `broadcastNoticeCode`). Renaming one needs a decode
// alias, or older records fall back to their stored English text.

enum SwapFailureOperation {
  tokenList,
  quote,
  start,
  refreshStatus,
  submitDeposit,
  sendZecDeposit,
}

enum SwapFailureSurface { swap, pay }

enum SwapFailureCategory {
  unsupportedAsset,
  amountTooLow,
  amountPrecision,
  invalidRouteOrAddress,
  noQuoteOrLiquidity,
  torBlocked,
  serviceUnavailable,
  networkTimeout,
  unverifiedResponse,
  retryLater,
  zecDepositFunding,
  zecDepositIronwoodFunding,
  walletPreflight,
  depositNotFound,
  depositRejected,
  unknown,
}

/// Swap and Pay messages that are not provider failures.
enum SwapNoticeKind {
  noActiveAccount,
  insufficientShieldedBalanceForFee,
  maxAmountUnavailable,
  activeAccountChanged,
  receiveAddressUnavailable,
  privateReceiveAddressPreparationFailed,
  privateReceiveAddressUnavailable,
  privateReceiveAddressLimit,
  depositIntentMissing,
  broadcastPartial,
  broadcastPending,
  broadcastUnknown,
  broadcastStorageFailed,
  broadcastUncertain,
  networkUpgradeHold,
  networkUpgradeScheduleChanged,
  startNotFinished,
  nearSwapPrivacyUnknown,
  recoveryUpdateRequired,
}

/// A message that swap state or a persisted swap record keeps. It records
/// what happened; [text] builds the copy in the display language.
sealed class SwapMessage {
  const SwapMessage();

  String text(AppLocalizations l10n);
}

/// A provider or wallet failure, classified by `swapFailureCategory`.
final class SwapFailureMessage extends SwapMessage {
  const SwapFailureMessage(
    this.operation,
    this.category, {
    this.surface = SwapFailureSurface.swap,
  });

  final SwapFailureOperation operation;
  final SwapFailureCategory category;

  /// Pay and Swap word the amount and Tor failures differently.
  final SwapFailureSurface surface;

  @override
  String text(AppLocalizations l10n) =>
      swapFailureText(l10n, operation, category, surface);

  @override
  bool operator ==(Object other) =>
      other is SwapFailureMessage &&
      other.operation == operation &&
      other.category == category &&
      other.surface == surface;

  @override
  int get hashCode => Object.hash(operation, category, surface);

  @override
  String toString() =>
      'SwapFailureMessage(${operation.name}, ${category.name}, ${surface.name})';
}

final class SwapNotice extends SwapMessage {
  const SwapNotice(this.kind);

  final SwapNoticeKind kind;

  @override
  String text(AppLocalizations l10n) => switch (kind) {
    SwapNoticeKind.noActiveAccount => l10n.commonNoActiveAccount,
    SwapNoticeKind.insufficientShieldedBalanceForFee =>
      l10n.sendInsufficientBalanceToCoverFeeShielded,
    SwapNoticeKind.maxAmountUnavailable => l10n.sendMaxUnavailable,
    SwapNoticeKind.activeAccountChanged => l10n.swapNoticeAccountChanged,
    SwapNoticeKind.receiveAddressUnavailable =>
      l10n.swapNoticeReceiveAddressUnavailable,
    SwapNoticeKind.privateReceiveAddressPreparationFailed =>
      l10n.swapNoticePrivateReceiveAddressPreparationFailed,
    SwapNoticeKind.privateReceiveAddressUnavailable =>
      l10n.swapNoticePrivateReceiveAddressUnavailable,
    SwapNoticeKind.privateReceiveAddressLimit =>
      l10n.swapNoticePrivateReceiveAddressLimit,
    SwapNoticeKind.depositIntentMissing => l10n.swapNoticeDepositIntentMissing,
    SwapNoticeKind.broadcastPartial => l10n.swapNoticeBroadcastPartial,
    SwapNoticeKind.broadcastPending => l10n.swapNoticeBroadcastPending,
    SwapNoticeKind.broadcastUnknown => l10n.swapNoticeBroadcastUnknown,
    SwapNoticeKind.broadcastStorageFailed => l10n.swapNoticeBroadcastNotStored,
    SwapNoticeKind.broadcastUncertain => l10n.swapNoticeBroadcastUncertain,
    SwapNoticeKind.networkUpgradeHold =>
      l10n.sendPaymentRequestCheckUpgradeHold,
    SwapNoticeKind.networkUpgradeScheduleChanged =>
      l10n.sendPaymentRequestCheckUpgradeScheduleChanged,
    SwapNoticeKind.startNotFinished => l10n.swapNoticeStartNotFinished,
    SwapNoticeKind.nearSwapPrivacyUnknown =>
      l10n.swapNoticeNearSwapPrivacyUnknown,
    SwapNoticeKind.recoveryUpdateRequired => l10n.swapRecoveryUpdateRequired,
  };

  @override
  bool operator ==(Object other) => other is SwapNotice && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'SwapNotice(${kind.name})';
}

/// A deposit broadcast result as Rust's sentences (`BroadcastNotice`). Its
/// English is the text Rust wrote.
final class SwapBroadcastMessage extends SwapMessage {
  /// Null when a notice has a kind this build does not know; keep Rust's
  /// text as a [SwapLiteralMessage] then.
  static SwapBroadcastMessage? tryFrom(List<BroadcastNotice> notices) {
    if (broadcastNoticeText(_englishL10n, notices) == null) return null;
    return SwapBroadcastMessage._(List.unmodifiable(notices));
  }

  const SwapBroadcastMessage._(this.notices);

  final List<BroadcastNotice> notices;

  @override
  String text(AppLocalizations l10n) => broadcastNoticeText(l10n, notices)!;

  @override
  bool operator ==(Object other) =>
      other is SwapBroadcastMessage && listEquals(other.notices, notices);

  @override
  int get hashCode => Object.hashAll(notices);

  @override
  String toString() =>
      'SwapBroadcastMessage(${notices.map((n) => n.kind).join(', ')})';
}

/// Text shown as it is: Rust and SDK errors and stored text that no code describes.
final class SwapLiteralMessage extends SwapMessage {
  const SwapLiteralMessage(this.value);

  final String value;

  @override
  String text(AppLocalizations l10n) => value;

  @override
  bool operator ==(Object other) =>
      other is SwapLiteralMessage && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SwapLiteralMessage($value)';
}

String swapFailureText(
  AppLocalizations l10n,
  SwapFailureOperation operation,
  SwapFailureCategory category,
  SwapFailureSurface surface,
) {
  final pay = surface == SwapFailureSurface.pay;
  final statusUpdate =
      operation == SwapFailureOperation.refreshStatus ||
      operation == SwapFailureOperation.submitDeposit;
  return switch (category) {
    SwapFailureCategory.unsupportedAsset =>
      statusUpdate
          ? l10n.swapFailureStatusAssetUnsupported
          : l10n.swapFailureAssetUnavailable,
    SwapFailureCategory.amountTooLow =>
      pay ? l10n.swapFailureAmountTooLowPay : l10n.swapFailureAmountTooLowSwap,
    SwapFailureCategory.amountPrecision => l10n.swapFailureAmountPrecision,
    SwapFailureCategory.invalidRouteOrAddress => l10n.swapFailureRouteRejected,
    SwapFailureCategory.noQuoteOrLiquidity => l10n.swapFailureNoQuote,
    SwapFailureCategory.torBlocked =>
      pay ? l10n.swapFailureTorBlockedPay : l10n.swapFailureTorBlockedSwap,
    SwapFailureCategory.serviceUnavailable =>
      statusUpdate
          ? l10n.swapFailureStatusAutoRefresh
          : l10n.swapFailureServiceUnavailable,
    SwapFailureCategory.networkTimeout => switch (operation) {
      SwapFailureOperation.quote => l10n.swapFailureQuoteTimeout,
      _ when statusUpdate => l10n.swapFailureStatusAutoRefresh,
      _ => l10n.swapFailureRequestTimeout,
    },
    SwapFailureCategory.unverifiedResponse =>
      operation == SwapFailureOperation.quote
          ? l10n.swapFailureQuoteUnverified
          : l10n.swapFailureResponseUnverified,
    SwapFailureCategory.retryLater =>
      statusUpdate
          ? l10n.swapFailureStatusAutoRefresh
          : l10n.swapFailureStillProcessing,
    SwapFailureCategory.zecDepositFunding => l10n.swapFailureZecDepositFunding,
    SwapFailureCategory.zecDepositIronwoodFunding =>
      pay
          ? l10n.swapFailureZecDepositIronwoodFundingPay
          : l10n.swapFailureZecDepositIronwoodFunding,
    SwapFailureCategory.walletPreflight => l10n.swapFailureZecDepositPreflight,
    SwapFailureCategory.depositNotFound => l10n.swapFailureDepositNotIndexed,
    SwapFailureCategory.depositRejected => l10n.swapFailureDepositRejected,
    SwapFailureCategory.unknown => switch (operation) {
      SwapFailureOperation.tokenList => l10n.swapFailureTokensUnavailable,
      SwapFailureOperation.quote => l10n.swapFailureQuoteUnavailable,
      SwapFailureOperation.start => l10n.swapFailureStartFailed,
      SwapFailureOperation.refreshStatus => l10n.swapFailureRefreshFailed,
      SwapFailureOperation.submitDeposit => l10n.swapFailureDepositSubmitFailed,
      SwapFailureOperation.sendZecDeposit =>
        l10n.swapFailureZecDepositSendFailed,
    },
  };
}

// Persistence.
//
// A record keeps the code under `<field>Code` and the English text under
// `<field>`. Released builds read and show only the English text, so a
// downgrade still shows the message; this build prefers the code.

final _englishL10n = lookupAppLocalizations(const Locale('en'));

/// The code stored for [message]; null for a literal, whose text is the
/// record.
Map<String, Object?>? swapMessageCodeToJson(SwapMessage? message) {
  return switch (message) {
    SwapFailureMessage(:final operation, :final category, :final surface) => {
      'type': 'failure',
      'operation': operation.name,
      'category': category.name,
      'surface': surface.name,
    },
    SwapNotice(:final kind) => {'type': 'notice', 'kind': kind.name},
    SwapBroadcastMessage(:final notices) => {
      'type': 'broadcast',
      'notices': broadcastNoticesToJson(notices),
    },
    SwapLiteralMessage() || null => null,
  };
}

/// The English text stored beside the code, for builds that read only text.
String? swapMessageLegacyText(SwapMessage? message) =>
    message?.text(_englishL10n);

/// Restores a stored message: the code when this build understands it,
/// otherwise the text, mapped to a code when an earlier build wrote it.
SwapMessage? swapMessageFromStored({Object? code, Object? text}) {
  final decoded = _swapMessageFromCode(code);
  if (decoded != null) return decoded;
  if (text is! String) return null;
  return swapMessageFromLegacyText(text);
}

/// Maps the English an earlier build stored to its code. Unknown text (Rust
/// errors, copy from builds this one does not know) is shown as stored.
SwapMessage swapMessageFromLegacyText(String text) =>
    _legacySwapMessages[text] ?? SwapLiteralMessage(text);

SwapMessage? _swapMessageFromCode(Object? code) {
  if (code is! Map) return null;
  switch (code['type']) {
    case 'failure':
      final operation = _enumByName(
        SwapFailureOperation.values,
        code['operation'],
      );
      final category = _enumByName(
        SwapFailureCategory.values,
        code['category'],
      );
      if (operation == null || category == null) return null;
      return SwapFailureMessage(
        operation,
        category,
        surface:
            _enumByName(SwapFailureSurface.values, code['surface']) ??
            SwapFailureSurface.swap,
      );
    case 'notice':
      final kind = _enumByName(SwapNoticeKind.values, code['kind']);
      return kind == null ? null : SwapNotice(kind);
    case 'broadcast':
      final notices = broadcastNoticesFromJson(code['notices']);
      return notices == null ? null : SwapBroadcastMessage.tryFrom(notices);
  }
  return null;
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Every message text builds before codes wrote into swap state, keyed by
/// that exact English. Several codes share one English text; any of them
/// renders the same copy in every language.
const _legacySwapMessages = <String, SwapMessage>{
  'Paused for the network upgrade. Try again in a few minutes.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.networkUpgradeHold,
  ),
  'The network upgrade changed the migration timing. Review the plan and start again.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.networkUpgradeScheduleChanged,
  ),
  "We couldn't refresh the latest status.\nWe'll keep trying and update this screen automatically.": // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.refreshStatus,
    SwapFailureCategory.serviceUnavailable,
  ),
  'Amount is too low for this payment.\nTry a larger amount.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.amountTooLow,
    surface: SwapFailureSurface.pay,
  ),
  'Amount is too low for this swap.\nTry a larger amount.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.amountTooLow,
  ),
  'Amount has too many decimal places.\nUse fewer decimals and try again.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.amountPrecision,
  ),
  'This route or address was rejected.\nEdit the details and request a new quote.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.invalidRouteOrAddress,
  ),
  'No quote is available for this route or amount.\nAdjust the amount, slippage, or asset and try again.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.noQuoteOrLiquidity,
  ),
  'Pay is unavailable over Tor because the service blocked this connection.\nTurn off Tor in Settings to pay.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.torBlocked,
    surface: SwapFailureSurface.pay,
  ),
  'Swap is unavailable over Tor because the service blocked this connection.\nTurn off Tor in Settings to use swap.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.torBlocked,
  ),
  'Not enough spendable ZEC to cover this swap and its network fee.\nTry a smaller amount or use Max.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.sendZecDeposit,
    SwapFailureCategory.zecDepositFunding,
  ),
  'ZEC deposit could not be prepared.\nCheck your balance and try again.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.sendZecDeposit,
    SwapFailureCategory.walletPreflight,
  ),
  'Deposit is not indexed yet.\nCheck again in a few minutes.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.refreshStatus,
    SwapFailureCategory.depositNotFound,
  ),
  'Deposit transaction was rejected.\nCheck the address, memo, and tx hash.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.submitDeposit,
    SwapFailureCategory.depositRejected,
  ),
  'Swap status uses an unsupported asset pair.\nDo not resend funds. Try again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.refreshStatus,
    SwapFailureCategory.unsupportedAsset,
  ),
  'This asset is not available for swap right now.\nChoose another asset or try again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.unsupportedAsset,
  ),
  'Swap service is temporarily unavailable.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.serviceUnavailable,
  ),
  'Quote request timed out.\nCheck your connection and try again.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.networkTimeout,
  ),
  'Request timed out.\nCheck your connection and try again.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.start,
    SwapFailureCategory.networkTimeout,
  ),
  'Swap service is still processing.\nWait a moment and try again.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.start,
    SwapFailureCategory.retryLater,
  ),
  'Quote response could not be verified.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.unverifiedResponse,
  ),
  'Swap response could not be verified.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.refreshStatus,
    SwapFailureCategory.unverifiedResponse,
  ),
  'Swap tokens could not be loaded.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.tokenList,
    SwapFailureCategory.unknown,
  ),
  'Quote is unavailable right now.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.quote,
    SwapFailureCategory.unknown,
  ),
  'Swap could not be started.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.start,
    SwapFailureCategory.unknown,
  ),
  'Could not refresh swap status.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.refreshStatus,
    SwapFailureCategory.unknown,
  ),
  'Deposit status could not be submitted.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.submitDeposit,
    SwapFailureCategory.unknown,
  ),
  'ZEC deposit could not be sent.\nTry again later.': // l10n-ignore: legacy persisted text
  SwapFailureMessage(
    SwapFailureOperation.sendZecDeposit,
    SwapFailureCategory.unknown,
  ),
  'No active account': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.noActiveAccount,
  ),
  'Insufficient shielded balance to cover fee': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.insufficientShieldedBalanceForFee,
  ),
  'Max amount unavailable': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.maxAmountUnavailable,
  ),
  'Active account changed. Review the quote again before starting.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.activeAccountChanged,
  ),
  'Could not prepare a fresh wallet receive address. Retry after wallet sync or close older pending swaps before requesting a new quote.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.receiveAddressUnavailable,
  ),
  'ZEC deposit was broadcast, but the saved swap intent was not found. Copy the transaction hash before leaving this screen.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.depositIntentMissing,
  ),
  'Some deposit transactions may have reached the network. Check activity before trying again.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.broadcastPartial,
  ),
  'The deposit was created locally but could not be broadcast. Check activity before trying again.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.broadcastPending,
  ),
  'The transaction may have reached the network, but confirmation timed out. Check activity before trying again.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.broadcastUnknown,
  ),
  'The transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.broadcastStorageFailed,
  ),
  'The deposit status is uncertain. Check activity before trying again.': // l10n-ignore: legacy persisted text
  SwapNotice(
    SwapNoticeKind.broadcastUncertain,
  ),
};

@visibleForTesting
Map<String, SwapMessage> get swapLegacyMessagesForTest => _legacySwapMessages;
