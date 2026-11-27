/// Proxy delegation and delegate mode copy that code picks from a code or a
/// condition. Plain strings are ARB messages the screens read directly.
library;

import '../../../core/l10n/l10n.dart';
import 'delegate_mode_models.dart';

/// How a delegate is named in a sentence: `@handle`.
String proxyDelegateName(String handle) => '@$handle';

/// One delegate's part of the round screen's split, for example
/// `4 ZEC to @alice`; just the [name] until the amount is planned.
String proxySplitToCopy(
  AppLocalizations l10n, {
  required String? amount,
  required String name,
}) => amount == null ? name : l10n.proxySplitTo(amount, name);

/// Why a suspended or retired delegate [name] can't be chosen.
String proxyBlockedCopy(
  AppLocalizations l10n,
  String name, {
  required bool retired,
}) =>
    retired ? l10n.proxyBlockedRetired(name) : l10n.proxyBlockedSuspended(name);

/// Copy for an attester answer (contracts-v1 section 12.4), or for none
/// when [error] is null. [retryTime] is the formatted `retry_after`, when
/// given.
String delegateVerifierErrorCopy(
  AppLocalizations l10n,
  DelegateVerifierError? error, {
  String? retryTime,
}) => switch (error) {
  DelegateVerifierError.badRequest => l10n.delegateVerifierBadRequest,
  DelegateVerifierError.postNotFound => l10n.delegateVerifierPostNotFound,
  DelegateVerifierError.markerMismatch => l10n.delegateVerifierMarkerMismatch,
  DelegateVerifierError.rateLimited =>
    retryTime == null
        ? l10n.delegateVerifierRateLimited
        : l10n.delegateVerifierRateLimitedUntil(retryTime),
  DelegateVerifierError.providerUnavailable =>
    retryTime == null
        ? l10n.delegateVerifierProviderUnavailable
        : l10n.delegateVerifierProviderUnavailableUntil(retryTime),
  DelegateVerifierError.unknown => l10n.delegateVerifierUnknown,
  null => l10n.delegateVerifierUnreachable,
};

/// Copy for a chain rejection of REGISTER (contracts-v1 section 6).
String delegateRegisterRejectionCopy(
  AppLocalizations l10n,
  String codespace,
  int code,
) {
  if (codespace != 'vote') return l10n.delegateRegisterRejected;
  return switch (code) {
    59 => l10n.delegateRegisterClosed,
    60 => l10n.delegateRegistryFull,
    61 => l10n.delegateKeyRegisteredBefore,
    62 => l10n.delegateHandleTaken,
    64 || 65 => l10n.delegateAttestationRejected,
    66 => l10n.delegateKeyUnregistrable,
    _ => l10n.delegateRegisterRejected,
  };
}

/// DG-8's approximate count for [atLeast] delegations, the only delegation
/// count Vizor shows anywhere.
String delegateCountCopy(AppLocalizations l10n, BigInt atLeast) =>
    atLeast == BigInt.zero
    ? l10n.delegateCountNone
    : l10n.delegateCountAtLeast(atLeast.toInt());

/// Copy for a ballot rejection (contracts section 6).
String delegateBallotRejectionCopy(
  AppLocalizations l10n,
  String? codespace,
  int? code,
) {
  if (codespace != 'vote') return l10n.delegateBallotRejected;
  return switch (code) {
    3 => l10n.delegateBallotUnknownRound,
    4 => l10n.delegateBallotTooLate,
    50 => l10n.delegateBallotRoundNoBallots,
    53 => l10n.delegateNoEntryForKey,
    54 => l10n.delegateSuspended,
    55 => l10n.delegateRetiredBallot,
    57 => l10n.delegateDifferentBallotOnChain,
    58 => l10n.delegateBallotInvalidOption,
    _ => l10n.delegateBallotRejected,
  };
}

/// Copy for a rejected Retire (contracts-v1 section 6).
String delegateRetireRejectionCopy(
  AppLocalizations l10n,
  String codespace,
  int code,
) {
  if (codespace == 'vote' && code == 54) return l10n.delegateRetireSuspended;
  if (codespace == 'vote' && code == 53) return l10n.delegateNoEntryForKey;
  return l10n.delegateRetireFailed;
}
