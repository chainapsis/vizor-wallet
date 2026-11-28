/// The delegate-mode values the screens read. The client API's types
/// (contracts-v1 section 15.1) are the bridge's own, exported here; the rest
/// are the Vizor-side values the repository builds around them from the
/// attester API (section 12.4), the vote servers' answers and the proven
/// registry entry.
library;

import 'package:flutter/foundation.dart';

import '../../../rust/api/proxy_delegate.dart'
    show ApiBallotSubmitKind, ApiBallotSubmitResult, ApiDelegateRound;
import '../../../rust/third_party/zcash_voting/wire.dart'
    show DelegateEntryView, DelegateKeyInfo, DelegateModeStatus;
import '../voting_flow_models.dart';
import 'proxy_delegation_repository.dart';

export '../../../rust/api/proxy_delegate.dart'
    show
        ApiBallotPreflight,
        ApiBallotSubmitKind,
        ApiBallotSubmitResult,
        ApiDelegateRound;
export '../../../rust/third_party/zcash_voting/wire.dart'
    show
        DelegateAttestation,
        DelegateBallotBlock,
        DelegateEntryView,
        DelegateKeyInfo,
        DelegateModeStatus,
        DelegateVerifierError,
        DelegateVerifierRefusal;

/// Revealed pool shares per delegation commitment at most. A pool's reveal
/// count R bounds its delegations between `ceil(R / 16)` and R.
const kDelegateSharesPerDelegation = 16;

/// Equality for variants without fields: any two instances are equal.
mixin _UnitVariant {
  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// What the screens ask of a ballot's submit outcome.
extension DelegateBallotSubmitOutcome on ApiBallotSubmitResult {
  /// The chain rejected the ballot; clients key on (`codespace`, `code`).
  bool get rejected => kind == ApiBallotSubmitKind.rejected;

  /// Whether coordinators can lift the cause of a rejection before voting
  /// ends: the entry is suspended (`vote`/54). The same ballot is then
  /// checked again rather than given up.
  bool get blocksForNow => rejected && codespace == 'vote' && code == 54;
}

/// The delegate key this device holds and its registry entry, with the
/// delegate's picture in Vizor's list. Delegate mode is app-level: it does
/// not belong to a wallet account. The entry's fields come from its proof,
/// never from the device's records alone.
@immutable
class DelegateModeView {
  /// Creates the view.
  const DelegateModeView({this.status, this.picture});

  /// zcash_voting's status, or null when the device holds no key.
  final DelegateModeStatus? status;

  /// This delegate's picture in Vizor's list, when the list names it.
  final ProxyDelegatePicture? picture;

  /// The device's delegate key, or null when it holds none.
  DelegateKeyInfo? get key => status?.key;

  /// The key's proven entry, or null before the registration lands.
  DelegateEntryView? get entry => status?.entry;

  /// A signed registration is stored and has not landed yet.
  bool get registrationPending => status?.registrationPending ?? false;

  /// The registration landed.
  bool get registered => entry != null;

  /// Coordinators suspended the entry.
  bool get suspended => entry?.status == DelegateEntryStatus.suspended;

  /// The entry is retired, for good.
  bool get retired => entry?.status == DelegateEntryStatus.retired;
}

/// The rounds holding a ballot this device signed, by id, and whether every
/// round could be read. When not, discovery runs again for the rest.
typedef DelegateStoredBallotRounds = ({List<String> roundIds, bool complete});

/// What one background resend of a stored ballot found.
sealed class DelegateBallotResend {
  const DelegateBallotResend();

  /// The stored ballot was posted and the vote servers gave [result], or
  /// the round's list shows a different ballot, a code 57 [result].
  const factory DelegateBallotResend.posted(ApiBallotSubmitResult result) =
      DelegateBallotResendPosted;

  /// Nothing is owed any more: no ballot is stored, the round's list shows
  /// one, or the entry is retired.
  const factory DelegateBallotResend.done() = DelegateBallotResendDone;

  /// The entry is suspended, which may be lifted before voting ends, so
  /// nothing was posted and a later resend checks again.
  const factory DelegateBallotResend.blocked() = DelegateBallotResendBlocked;
}

/// See [DelegateBallotResend.posted].
final class DelegateBallotResendPosted extends DelegateBallotResend {
  /// Creates the outcome.
  const DelegateBallotResendPosted(this.result);

  /// The vote servers' answer.
  final ApiBallotSubmitResult result;

  @override
  bool operator ==(Object other) =>
      other is DelegateBallotResendPosted && other.result == result;

  @override
  int get hashCode => Object.hash(DelegateBallotResendPosted, result);
}

/// See [DelegateBallotResend.done].
final class DelegateBallotResendDone extends DelegateBallotResend
    with _UnitVariant {
  /// Creates the outcome.
  const DelegateBallotResendDone();
}

/// See [DelegateBallotResend.blocked].
final class DelegateBallotResendBlocked extends DelegateBallotResend
    with _UnitVariant {
  /// Creates the outcome.
  const DelegateBallotResendBlocked();
}

/// A proxy round as the delegate sees it: zcash_voting's view of it, with
/// the title and questions Vizor already holds.
@immutable
class DelegateRound {
  /// Creates the round view.
  const DelegateRound({
    required this.view,
    required this.title,
    required this.proposals,
  });

  /// zcash_voting's view: the deadline, the revealed pool shares R (the
  /// dashboard shows at least `ceil(R / 16)` delegations and never R
  /// itself), the delegate's ballot as published, a ballot this device
  /// signed but has not seen on chain, and why it cannot sign one.
  final ApiDelegateRound view;

  /// Round title.
  final String title;

  /// Every question of the round in id order; a ballot answers all of them.
  final List<VotingProposalView> proposals;

  /// The round's `vote_end_time`, the ballot deadline.
  DateTime get voteEndTime => proxyTimeFromSeconds(view.voteEndTime);

  /// The published ballot's options, or null while none is on chain.
  List<int>? get onChainOptions => switch (view.ballot.kind) {
    ApiDelegateBallotKind.submitted ||
    ApiDelegateBallotKind.counted => view.ballot.options,
    _ => null,
  };
}

/// Outcome of signing REGISTER and submitting it on chain.
sealed class DelegateRegisterResult {
  const DelegateRegisterResult();

  /// The device's key is the key of entry
  /// [DelegateRegistered.delegateIndex].
  const factory DelegateRegisterResult.registered({
    required int delegateIndex,
  }) = DelegateRegistered;

  /// The chain rejected the op (contracts section 6).
  const factory DelegateRegisterResult.rejected({
    required String codespace,
    required int code,
    required String reason,
  }) = DelegateRegisterRejected;
}

/// See [DelegateRegisterResult.registered].
final class DelegateRegistered extends DelegateRegisterResult {
  /// Creates the result.
  const DelegateRegistered({required this.delegateIndex});

  /// The index the chain assigned the entry.
  final int delegateIndex;

  @override
  bool operator ==(Object other) =>
      other is DelegateRegistered && other.delegateIndex == delegateIndex;

  @override
  int get hashCode => Object.hash(DelegateRegistered, delegateIndex);
}

/// See [DelegateRegisterResult.rejected].
final class DelegateRegisterRejected extends DelegateRegisterResult {
  /// Creates the result.
  const DelegateRegisterRejected({
    required this.codespace,
    required this.code,
    required this.reason,
  });

  /// ABCI codespace.
  final String codespace;

  /// Registered error code.
  final int code;

  /// The chain's log line; diagnostic only.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is DelegateRegisterRejected &&
      other.codespace == codespace &&
      other.code == code &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(codespace, code, reason);
}

/// Outcome of Retire.
sealed class DelegateRetireResult {
  const DelegateRetireResult();

  /// The entry is retired, by this Retire or before it (code 55).
  const factory DelegateRetireResult.retired() = DelegateRetired;

  /// The chain refused the retirement, such as a suspended entry's
  /// (code 54).
  const factory DelegateRetireResult.rejected({
    required String codespace,
    required int code,
    required String reason,
  }) = DelegateRetireRejected;
}

/// See [DelegateRetireResult.retired].
final class DelegateRetired extends DelegateRetireResult with _UnitVariant {
  /// Creates the result.
  const DelegateRetired();
}

/// See [DelegateRetireResult.rejected].
final class DelegateRetireRejected extends DelegateRetireResult {
  /// Creates the result.
  const DelegateRetireRejected({
    required this.codespace,
    required this.code,
    required this.reason,
  });

  /// ABCI codespace.
  final String codespace;

  /// Registered error code.
  final int code;

  /// The chain's log line; diagnostic only.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is DelegateRetireRejected &&
      other.codespace == codespace &&
      other.code == code &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(codespace, code, reason);
}
