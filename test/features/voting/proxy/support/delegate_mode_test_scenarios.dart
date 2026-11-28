import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';

import 'mock_delegate_mode_repository.dart';
import 'mock_proxy_delegation_repository.dart';
import 'proxy_test_scenarios.dart';
import 'proxy_values.dart';

export 'proxy_test_scenarios.dart' show kProxyTestNow;

/// Round every delegate-mode test uses.
const kDelegateTestRoundId = 'round-1';

/// The registered test delegate's key.
final kDelegateTestKey = mockDelegateKey(100);

/// The export of [kDelegateTestKey].
final kDelegateTestSecret = mockDelegateSecret(100);

/// A round ending three days after [kProxyTestNow] unless [voteEnd] says
/// otherwise, with the development round's three questions and 37 revealed
/// pool shares.
DelegateMockRound delegateTestRound({
  DateTime? voteEnd,
  ApiDelegateBallotView? ballot,
}) {
  final delegator = ProxyMockScenario.development(now: kProxyTestNow);
  return DelegateMockRound(
    roundId: kDelegateTestRoundId,
    title: 'Test proxy round',
    proposals: delegator.round.proposals,
    voteEndTime: voteEnd ?? kProxyTestNow.add(const Duration(days: 3)),
    revealedShares: BigInt.from(37),
    ballot: ballot,
  );
}

/// A device with no delegate key yet, and one running round.
DelegateModeMockScenario delegateFreshScenario() =>
    DelegateModeMockScenario(rounds: [delegateTestRound()]);

/// A device registered as delegate #17 (@alice_votes on X), with the
/// entry in [entryStatus], and one running round.
DelegateModeMockScenario delegateRegisteredScenario({
  DelegateEntryStatus entryStatus = DelegateEntryStatus.active,
  List<DelegateMockRound>? rounds,
}) {
  return DelegateModeMockScenario(
    status: delegateModeView(
      key: kDelegateTestKey,
      delegateIndex: 17,
      provider: ProxyDelegateProvider.x,
      handle: 'alice_votes',
      entryStatus: entryStatus,
    ),
    rounds: rounds ?? [delegateTestRound()],
  );
}

/// A device whose key awaits its registration, and one running round.
DelegateModeMockScenario delegateUnregisteredScenario({
  bool registrationPending = false,
}) => DelegateModeMockScenario(
  status: delegateModeView(
    key: kDelegateTestKey,
    registrationPending: registrationPending,
  ),
  rounds: [delegateTestRound()],
);
