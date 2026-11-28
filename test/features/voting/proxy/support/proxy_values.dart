import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';

/// A delegate's ballot view of [kind] with [options], one per proposal.
ApiDelegateBallotView proxyBallot(
  ApiDelegateBallotKind kind, [
  List<int> options = const [],
]) => ApiDelegateBallotView(kind: kind, options: Uint32List.fromList(options));

/// Matches a ballot view of [kind] with [options].
Matcher isProxyBallot(
  ApiDelegateBallotKind kind, [
  List<int> options = const [],
]) => isA<ApiDelegateBallotView>()
    .having((ballot) => ballot.kind, 'kind', kind)
    .having((ballot) => ballot.options, 'options', options);

/// A committed delegation's view; on X with no ballot yet unless said.
ApiProxyDelegationView proxyView({
  required int delegateIndex,
  ProxyDelegateProvider provider = ProxyDelegateProvider.x,
  required String handle,
  required BigInt ballots,
  required ProxyDelegationStage stage,
  ApiDelegateBallotView? ballot,
}) => ApiProxyDelegationView(
  delegateIndex: delegateIndex,
  provider: provider,
  handle: handle,
  ballots: ballots,
  stage: stage,
  ballot: ballot ?? proxyBallot(ApiDelegateBallotKind.noBallotYet),
);

/// The delegation job's snapshot, with every flag off unless set.
ApiProxyDelegationProgress proxyProgress({
  required List<ApiProxyDelegationView> delegations,
  bool plannedImmediate = false,
  bool immediateRevealConfirmed = false,
  bool refusedByChain = false,
}) => ApiProxyDelegationProgress(
  delegations: delegations,
  plannedImmediate: plannedImmediate,
  immediateRevealConfirmed: immediateRevealConfirmed,
  refusedByChain: refusedByChain,
);

/// An active listing on X that is not new this round, with the key
/// `zvdk1<handle>`.
ProxyDelegateListing proxyListingOf({
  required int index,
  required String handle,
  required bool reviewed,
  String? displayName,
  Uint8List? picture,
}) => ProxyDelegateListing(
  index: index,
  provider: ProxyDelegateProvider.x,
  handle: handle,
  key: DelegateKeyInfo(dk: 'zvdk1$handle', fingerprint: 'qqqs-yqcy-q5rq-wzqf'),
  reviewed: reviewed,
  displayName: displayName,
  picture: picture,
  newThisRound: false,
  status: DelegateEntryStatus.active,
);

/// The view of a device holding [key], with an entry once [delegateIndex]
/// is given: [entryStatus] defaults to active.
DelegateModeView delegateModeView({
  DelegateKeyInfo? key,
  int? delegateIndex,
  ProxyDelegateProvider provider = ProxyDelegateProvider.x,
  String handle = 'alice_votes',
  DelegateEntryStatus entryStatus = DelegateEntryStatus.active,
  bool registrationPending = false,
  ProxyDelegatePicture? picture,
}) => DelegateModeView(
  status: key == null
      ? null
      : DelegateModeStatus(
          key: key,
          entry: delegateIndex == null
              ? null
              : DelegateEntryView(
                  delegateIndex: delegateIndex,
                  provider: provider,
                  handle: handle,
                  proofId: '1790000000000000000',
                  status: entryStatus,
                  statusReason: 0,
                ),
          registrationPending: registrationPending,
        ),
  picture: picture,
);

/// [view] with its entry's status changed to [entryStatus].
DelegateModeView delegateModeViewWith(
  DelegateModeView view,
  DelegateEntryStatus entryStatus,
) => delegateModeView(
  key: view.key,
  delegateIndex: view.entry?.delegateIndex,
  provider: view.entry?.provider ?? ProxyDelegateProvider.x,
  handle: view.entry?.handle ?? '',
  entryStatus: entryStatus,
  picture: view.picture,
);

/// A ballot's submit outcome of [kind].
ApiBallotSubmitResult ballotSubmit(ApiBallotSubmitKind kind) =>
    ApiBallotSubmitResult(kind: kind);

/// The chain's rejection of a ballot with ([codespace], [code]).
ApiBallotSubmitResult ballotRejected(
  int code, {
  String codespace = 'vote',
  String reason = '',
}) => ApiBallotSubmitResult(
  kind: ApiBallotSubmitKind.rejected,
  codespace: codespace,
  code: code,
  reason: reason,
);
