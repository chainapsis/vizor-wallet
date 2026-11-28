import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';

import 'mock_proxy_delegation_repository.dart';
import 'proxy_values.dart';

/// Round every proxy test uses.
const kProxyTestRoundId = 'round-1';

/// Fixed "now" for proxy tests.
final kProxyTestNow = DateTime(2026, 10, 7, 12);

/// The development scenario pinned to [kProxyTestNow], with a vote end three
/// days out unless [voteEnd] says otherwise.
ProxyMockScenario proxyTestScenario({
  DateTime? voteEnd,
  ApiProxyAvailability availability = const ApiProxyAvailability(
    kind: ApiProxyAvailabilityKind.available,
    usedElsewhere: false,
  ),
  BigInt? eligibleBallots,
}) {
  final scenario = ProxyMockScenario.development(now: kProxyTestNow);
  final round = scenario.round;
  scenario
    ..availability = availability
    ..round = ProxyRoundContext(
      roundId: kProxyTestRoundId,
      title: round.title,
      proposals: round.proposals,
      voteEndTime: voteEnd ?? kProxyTestNow.add(const Duration(days: 3)),
      eligibleBallots: eligibleBallots ?? BigInt.from(400),
    );
  return scenario;
}

/// The scenario's entry for [handle].
ProxyDelegateListing proxyEntry(ProxyMockScenario scenario, String handle) =>
    scenario.delegates.firstWhere((entry) => entry.handle == handle);

/// A committed allocation to [handles] with every delegation at [stage].
ApiProxyAllocationStatus proxyStatus(
  ProxyMockScenario scenario,
  List<String> handles, {
  ProxyDelegationStage stage = ProxyDelegationStage.handedOff,
  ApiDelegateBallotView? ballot,
  int ballotsEach = 100,
  int keptBallots = 100,
}) {
  return ApiProxyAllocationStatus(
    delegations: [
      for (final handle in handles)
        ApiProxyDelegationView(
          delegateIndex: proxyEntry(scenario, handle).index,
          provider: proxyEntry(scenario, handle).provider,
          handle: handle,
          ballots: BigInt.from(ballotsEach),
          stage: stage,
          ballot: ballot ?? proxyBallot(ApiDelegateBallotKind.noBallotYet),
        ),
    ],
    keptBallots: BigInt.from(keptBallots),
  );
}
