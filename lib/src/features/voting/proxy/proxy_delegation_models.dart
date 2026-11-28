/// The delegator types of the proxy delegation client API (contracts-v1
/// section 15.1), as the bridge generates them, with the constants and
/// derived values the screens share.
///
/// Rust `u64` fields are [BigInt] and `u32`/`u16` fields are [int]. An enum
/// that carries data crosses as a flat `Api*` struct with a `kind`.
library;

import '../../../rust/api/proxy_delegator.dart';
import '../../../rust/api/proxy_registry.dart';
import '../../../rust/third_party/zcash_voting/wire.dart';

export '../../../rust/api/proxy_delegator.dart'
    show
        ApiDelegateBallotKind,
        ApiDelegateBallotView,
        ApiGovNullifierProof,
        ApiProxyAllocationStatus,
        ApiProxyAvailability,
        ApiProxyAvailabilityKind,
        ApiProxyDelegationProgress,
        ApiProxyDelegationView;
export '../../../rust/api/proxy_registry.dart'
    show ApiConfirmedDelegate, ApiDelegateLookup, ApiDelegateLookupKind;
export '../../../rust/third_party/zcash_voting/wire.dart'
    show
        DelegateCheck,
        DelegateEntryStatus,
        DelegateKeyInfo,
        ProxyAllocationPreview,
        ProxyAllocationRequest,
        ProxyDelegateBrowse,
        ProxyDelegateChoice,
        ProxyDelegateListing,
        ProxyDelegateProvider,
        ProxyDelegationError,
        ProxyDelegationErrorKind,
        ProxyDelegationStage,
        ProxyPreviewDelegation;

/// Most delegates one allocation may name (plan section 4.4).
const kProxyMaxDelegates = 8;

/// Basis points in a whole allocation.
const kProxyFullBps = 10000;

/// Zatoshi in one ballot, the proxy weight unit (0.125 ZEC).
final kProxyZatoshiPerBallot = BigInt.from(12500000);

/// Converts a ballot count to zatoshi.
BigInt proxyBallotsToZatoshi(BigInt ballots) =>
    ballots * kProxyZatoshiPerBallot;

/// [time] in whole unix seconds, as the bridge takes times.
BigInt proxyUnixSeconds(DateTime time) =>
    BigInt.from(time.millisecondsSinceEpoch ~/ 1000);

/// Unix [seconds] as a local time.
DateTime proxyTimeFromSeconds(BigInt seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);

/// [error] for a log line: a registry error's description from
/// zcash_voting, which names no account data, or the error's type
/// otherwise.
String describeProxyRegistryError(Object error) =>
    error is ApiProxyRegistryError ? error.message : '${error.runtimeType}';

/// [error] for a log line, with a delegator error's kind and detail, which
/// the generated class does not print.
String describeProxyDelegationError(Object error) =>
    error is ProxyDelegationError
    ? 'ProxyDelegationError(${error.kind.name}' // l10n-ignore: error description for logs
          '${error.detail == null ? '' : ': ${error.detail}'})'
    : '$error';

/// What the screens derive from a listing.
extension ProxyDelegateListingChoice on ProxyDelegateListing {
  /// Whether a delegation to this delegate would be refused at confirm.
  bool get blocked => status != DelegateEntryStatus.active;

  /// The choice this entry contributes to an allocation request: the
  /// pre-proving check requires the proven entry at its index to hold
  /// exactly this provider, handle and key (contracts-v1 section 11.11).
  ProxyDelegateChoice choice(int percentBps) => ProxyDelegateChoice(
    delegateIndex: index,
    percentBps: percentBps,
    provider: provider,
    handle: handle,
    dk: key.dk,
  );
}

/// What the screens derive from a preview.
extension ProxyAllocationPreviewTotals on ProxyAllocationPreview {
  /// Ballots delegated across all delegates.
  BigInt get delegatedBallots =>
      delegations.fold(BigInt.zero, (sum, entry) => sum + entry.ballots);
}

/// What the screens derive from a committed allocation.
extension ProxyAllocationStatusTotals on ApiProxyAllocationStatus {
  /// Ballots delegated across all delegates.
  BigInt get delegatedBallots =>
      delegations.fold(BigInt.zero, (sum, view) => sum + view.ballots);
}
