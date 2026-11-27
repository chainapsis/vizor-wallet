import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

/// An active listing that is not new this round, with the key
/// `zvdk1<handle>` unless [dk] and [fingerprint] say otherwise.
ProxyDelegateListing proxyListingOf({
  required int index,
  ProxyDelegateProvider provider = ProxyDelegateProvider.x,
  required String handle,
  String? dk,
  String fingerprint = 'qqqs-yqcy-q5rq-wzqf',
  required bool reviewed,
  String? displayName,
  Uint8List? picture,
}) => ProxyDelegateListing(
  index: index,
  provider: provider,
  handle: handle,
  key: DelegateKeyInfo(dk: dk ?? 'zvdk1$handle', fingerprint: fingerprint),
  reviewed: reviewed,
  displayName: displayName,
  picture: picture,
  newThisRound: false,
  status: DelegateEntryStatus.active,
);
