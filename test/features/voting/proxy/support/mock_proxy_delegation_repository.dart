import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'proxy_values.dart';

/// Mutable inputs for [MockProxyDelegationRepository]. Tests change fields
/// between steps to move the mock through every state.
class ProxyMockScenario {
  /// Creates a scenario.
  ProxyMockScenario({
    required this.round,
    required this.delegates,
    this.availability = const ApiProxyAvailability(
      kind: ApiProxyAvailabilityKind.available,
      usedElsewhere: false,
    ),
    this.availabilityCannotVerify = false,
    this.listUnavailable = false,
    Set<int>? listed,
    Map<int, DelegateCheck>? checks,
    this.status,
  }) : listed = listed ?? {for (final entry in delegates) entry.index},
       checks = checks ?? {};

  /// The shared test round: the delegates and questions below.
  factory ProxyMockScenario.development({required DateTime now}) {
    final delegates = [
      for (final (i, seed) in _developmentDelegates.indexed)
        _developmentEntry(i + 1, seed),
    ];
    return ProxyMockScenario(
      round: ProxyRoundContext(
        roundId: 'mock-proxy-round',
        title: 'Mock proxy delegation round',
        proposals: _developmentProposals,
        voteEndTime: now.add(const Duration(days: 3)),
        eligibleBallots: BigInt.from(400),
      ),
      delegates: delegates,
      listed: {
        for (final (i, seed) in _developmentDelegates.indexed)
          if (seed.listed) i + 1,
      },
    );
  }

  /// Round facts; the mock answers every round id with these.
  ProxyRoundContext round;

  /// Every registered delegate the mock knows. Browse shows the ones in
  /// [listed], in order; search and paste find any of them.
  List<ProxyDelegateListing> delegates;

  /// The indices Vizor's wallet list has a row for.
  Set<int> listed;

  /// Result of [MockProxyDelegationRepository.availability].
  ApiProxyAvailability availability;

  /// Makes availability fail as a trust-anchor verification failure.
  bool availabilityCannotVerify;

  /// Browse has no verified wallet list.
  bool listUnavailable;

  /// Pre-proving check per delegate index; missing means ok.
  Map<int, DelegateCheck> checks;

  /// The committed allocation, or null before delegating.
  ApiProxyAllocationStatus? status;

  /// Makes the pre-proving check fail as it does when no proof host serves
  /// evidence the reader verifies.
  bool checkCannotVerify = false;
}

/// The delegator screens' test double.
class MockProxyDelegationRepository implements ProxyDelegationRepository {
  /// Creates a mock over [scenario].
  MockProxyDelegationRepository(this.scenario);

  /// Inputs; tests may change them between steps.
  final ProxyMockScenario scenario;

  /// Requests the screens committed, for assertions.
  final List<ProxyAllocationRequest> commits = [];

  /// Number of availability and check calls, for assertions.
  int availabilityCalls = 0;

  /// See [availabilityCalls].
  int checkCalls = 0;

  @override
  Future<ProxyRoundContext> roundContext(String roundId) async {
    final round = scenario.round;
    return ProxyRoundContext(
      roundId: roundId,
      title: round.title,
      proposals: round.proposals,
      voteEndTime: round.voteEndTime,
      eligibleBallots: round.eligibleBallots,
    );
  }

  @override
  Future<ApiProxyAvailability> availability(String roundId) async {
    availabilityCalls++;
    if (scenario.availabilityCannotVerify) {
      throw const ProxyDelegationError(
        kind: ProxyDelegationErrorKind.cannotVerify,
      );
    }
    return scenario.availability;
  }

  @override
  Future<ProxyDelegateBrowse> browse(String roundId) async {
    if (scenario.listUnavailable) {
      return const ProxyDelegateBrowse(listed: [], listUnavailable: true);
    }
    return ProxyDelegateBrowse(
      listed: [
        for (final entry in scenario.delegates)
          if (scenario.listed.contains(entry.index)) entry,
      ],
      listUnavailable: false,
    );
  }

  /// Exact handle search over the live entries: the handle,
  /// case-insensitive and with or without `@`.
  @override
  Future<List<ProxyDelegateListing>> search(
    String roundId,
    String query,
  ) async {
    var needle = query.trim().toLowerCase();
    if (needle.startsWith('@')) needle = needle.substring(1);
    return [
      for (final entry in scenario.delegates)
        if (entry.handle == needle &&
            entry.status != DelegateEntryStatus.retired)
          entry,
    ];
  }

  /// Paste or scan of a mock `zvdk1…` key.
  @override
  Future<ApiDelegateLookup> lookup(String roundId, String text) async =>
      switch (scenario.delegates
          .where((entry) => entry.key.dk == text.trim())
          .firstOrNull) {
        final entry? => ApiDelegateLookup(
          kind: ApiDelegateLookupKind.found,
          listing: entry,
        ),
        null => const ApiDelegateLookup(
          kind: ApiDelegateLookupKind.unrecognized,
        ),
      };

  @override
  Future<ProxyAllocationPreview> preview(
    ProxyAllocationRequest request,
  ) async => planMockProxyAllocation(
    request,
    eligibleBallots: scenario.round.eligibleBallots,
  );

  @override
  Future<List<ApiConfirmedDelegate>> checkDelegates(
    String roundId,
    List<ProxyDelegateChoice> choices,
  ) async {
    checkCalls++;
    if (scenario.checkCannotVerify) {
      throw const ProxyDelegationError(
        kind: ProxyDelegationErrorKind.cannotVerify,
      );
    }
    return [
      for (final choice in choices)
        ApiConfirmedDelegate(
          check: scenario.checks[choice.delegateIndex] ?? DelegateCheck.ok,
          listing: scenario.delegates
              .where((entry) => entry.index == choice.delegateIndex)
              .firstOrNull,
        ),
    ];
  }

  /// Checks the delegates again, as the real repository does, and commits
  /// only when every verdict is ok.
  @override
  Future<void> commit(
    ProxyAllocationRequest request, {
    required ProxyAllocationPreview confirmed,
  }) async {
    final checked = await checkDelegates(request.roundId, request.choices);
    if (checked.any((delegate) => delegate.check != DelegateCheck.ok)) {
      throw const ProxyReviewChangedException();
    }
    final preview = await this.preview(request);
    commits.add(request);
    final status = ApiProxyAllocationStatus(
      delegations: [
        for (final (i, choice) in request.choices.indexed)
          ApiProxyDelegationView(
            delegateIndex: choice.delegateIndex,
            provider: choice.provider,
            handle: choice.handle,
            ballots: preview.delegations[i].ballots,
            stage: ProxyDelegationStage.preparing,
            ballot: proxyBallot(ApiDelegateBallotKind.noBallotYet),
          ),
      ],
      keptBallots: preview.keptBallots,
    );
    scenario.status = status;
  }

  @override
  Future<ApiProxyAllocationStatus?> allocationStatus(String roundId) async =>
      scenario.status;
}

/// Stand-in for zcash_voting's planner (plan section 4.4, Rounding):
/// Hamilton largest remainder over the delegates and the kept share; then
/// at least one ballot per delegate, funded by the kept share or the largest
/// delegate. Packing is
/// not modelled: one bundle, one delegation commitment per delegate.
ProxyAllocationPreview planMockProxyAllocation(
  ProxyAllocationRequest request, {
  required BigInt eligibleBallots,
}) {
  final choices = request.choices;
  if (choices.isEmpty || choices.length > kProxyMaxDelegates) {
    throw ProxyDelegationError(
      kind: ProxyDelegationErrorKind.other,
      detail: 'needs 1 to $kProxyMaxDelegates delegates, got ${choices.length}',
    );
  }
  final assigned = choices.fold(0, (sum, choice) => sum + choice.percentBps);
  if (choices.any((choice) => choice.percentBps <= 0) ||
      assigned > kProxyFullBps) {
    throw const ProxyDelegationError(
      kind: ProxyDelegationErrorKind.other,
      detail: 'invalid split',
    );
  }
  if (eligibleBallots < BigInt.from(choices.length)) {
    throw const ProxyDelegationError(
      kind: ProxyDelegationErrorKind.notEnoughVotingPower,
    );
  }
  final weights = [
    for (final choice in choices) choice.percentBps,
    kProxyFullBps - assigned,
  ];
  final full = BigInt.from(kProxyFullBps);
  final ballots = [
    for (final weight in weights) eligibleBallots * BigInt.from(weight) ~/ full,
  ];
  final remainders = [
    for (final weight in weights)
      (eligibleBallots * BigInt.from(weight)).remainder(full),
  ];
  var leftover = eligibleBallots - ballots.fold(BigInt.zero, (a, b) => a + b);
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final i in order) {
    if (leftover <= BigInt.zero) break;
    ballots[i] += BigInt.one;
    leftover -= BigInt.one;
  }
  final keepIndex = weights.length - 1;
  for (var i = 0; i < choices.length; i++) {
    if (ballots[i] > BigInt.zero) continue;
    if (ballots[keepIndex] > BigInt.zero) {
      ballots[keepIndex] -= BigInt.one;
    } else {
      var donor = 0;
      for (var j = 1; j < choices.length; j++) {
        if (ballots[j] > ballots[donor]) donor = j;
      }
      ballots[donor] -= BigInt.one;
    }
    ballots[i] = BigInt.one;
  }
  return ProxyAllocationPreview(
    delegations: [
      for (final (i, choice) in choices.indexed)
        ProxyPreviewDelegation(
          delegateIndex: choice.delegateIndex,
          ballots: ballots[i],
        ),
    ],
    keptBallots: ballots[keepIndex],
    dcCount: choices.length,
    bundleCount: 1,
    singleShare: false,
  );
}

/// A deterministic mock fingerprint and `zvdk1` key for [seed].
DelegateKeyInfo mockProxyDelegateKey(String seed) {
  const alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final bytes = [
    ...sha256.convert(utf8.encode('mock-dk:$seed')).bytes,
    ...sha256.convert(utf8.encode('mock-dk-tail:$seed')).bytes,
  ];
  final chars = [for (final byte in bytes) alphabet[byte % 32]].join();
  final fingerprint = [
    for (var i = 0; i < 16; i += 4) chars.substring(i, i + 4),
  ].join('-');
  return DelegateKeyInfo(
    dk: 'zvdk1${chars.substring(0, 58)}',
    fingerprint: fingerprint,
  );
}

typedef _DevelopmentDelegate = ({
  String handle,
  String? name,
  String? statement,
  bool listed,
  ProxyDelegateProvider provider,
  bool retired,
  String? lookalikeOf,
  bool newThisRound,
});

const List<_DevelopmentDelegate> _developmentDelegates = [
  (
    handle: 'alice_votes',
    name: 'Alice Moreau',
    statement: 'I vote for privacy upgrades and a careful fee policy.',
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'bjorn_dev',
    name: 'Bjorn Lindqvist',
    statement: null,
    listed: true,
    provider: ProxyDelegateProvider.gitHub,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'chidi_node',
    name: 'Chidi Okafor',
    statement: 'Node operator. I post my reasoning before every vote.',
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: null,
    newThisRound: true,
  ),
  (
    handle: 'dana_research',
    name: 'Dana Reyes',
    statement: 'Protocol researcher.',
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'emeka',
    name: 'Emeka Nwosu',
    statement: null,
    listed: true,
    provider: ProxyDelegateProvider.gitHub,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'freya_z',
    name: 'Freya Holm',
    statement: 'Wallet developer.',
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'gustavo',
    name: 'Gustavo Prado',
    statement: null,
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'hana_k',
    name: 'Hana Kobayashi',
    statement: 'Grants reviewer.',
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'ines_p',
    name: 'Ines Pereira',
    statement: null,
    listed: true,
    provider: ProxyDelegateProvider.gitHub,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'jonas_vote',
    name: 'Jonas Weber',
    statement: 'Community organizer.',
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'a1ice_votes',
    name: null,
    statement: null,
    listed: false,
    provider: ProxyDelegateProvider.x,
    retired: false,
    lookalikeOf: 'alice_votes',
    newThisRound: true,
  ),
  (
    handle: 'kofi_m',
    name: null,
    statement: null,
    listed: false,
    provider: ProxyDelegateProvider.gitHub,
    retired: false,
    lookalikeOf: null,
    newThisRound: false,
  ),
  (
    handle: 'lena_old',
    name: 'Lena Fischer',
    statement: null,
    listed: true,
    provider: ProxyDelegateProvider.x,
    retired: true,
    lookalikeOf: null,
    newThisRound: false,
  ),
];

/// Builds the test entry at [index] from [seed].
ProxyDelegateListing _developmentEntry(int index, _DevelopmentDelegate seed) {
  return ProxyDelegateListing(
    index: index,
    key: mockProxyDelegateKey(seed.handle),
    reviewed: seed.listed && !seed.retired,
    provider: seed.provider,
    handle: seed.handle,
    displayName: seed.listed ? seed.name : null,
    statement: seed.listed ? seed.statement : null,
    newThisRound: seed.newThisRound,
    status: seed.retired
        ? DelegateEntryStatus.retired
        : DelegateEntryStatus.active,
    lookalikeOf: seed.lookalikeOf,
    picture: switch (seed.listed ? _developmentPictureOf[seed.handle] : null) {
      final picture? => base64Decode(_developmentPictures[picture]),
      null => null,
    },
  );
}

/// Two 128 px lossless WebP silhouettes.
const _developmentPictures = [
  'UklGRqgBAABXRUJQVlA4TJsBAAAvf8AfAM1VICICHghYDiwJAIACAAAAAAAAAAAAAIAD'
      'ANAAAAAACgAAAAAAAAAAAAAAAADo+RhJ8jLzl13ngWwCAAAAAJz/AAAAAAAHAAAAAAAA'
      'AAAAAAAAAAAAAAAAAAAQCAAAAADggWwCAAAAAJz/AAAAAIBAAAAAAAAAAAAAAAAAAAAA'
      'AAAAAAAAOAAAAAAQ+W+H/7da93CcdcG9dcFJVsOI1XCMBaMWHGLBuAUnWA0zVkO8BbMW'
      'vJwF8xZEW7DCgmAL1ljwWhassuBLtWCdBX9T6oN19cGXWh+sqg9eqz5YUx8E1wcr6oPo'
      '+mC+Pni5+mC2Poivr2GmvoYT6oPx+uCQ+mC0PjimvoaR+hpOqu+C+/ouOK6+e/hzY43A'
      'OdYHRqwPnGA1zFgN4dYFs9YFuVbDGqsh02pYZzUEWrDWgjSrYbXVEGXBDguCLNhjQYrV'
      'sMtqiLBgpwUBFuy1YLsFuy3YbMF+Cx7dggQLNlqQYcE2C1IseGgLcizYYkGSBQ9sQZYF'
      'j2tBmgVflgV5FjyqBYkW/KAsyLTgVwIA',
  'UklGRqgBAABXRUJQVlA4TJsBAAAvf8AfAM1VICICHghYDiwJAIACAAAAAAAAAADgAADQ'
      'AAAAAAAAAAAKAAAAAAAAAAAAAADo+RhJ8jLzl13ngWwCAAAAAJz/AAAAAAAAgAABAAAA'
      'AAAAAAAAAAAAAAAAADgAAAAAAADggWwCAAAAAJz/AAAABwAAAAAAAAAAAAAAAAAAAAAA'
      'AAAAAAAAAEAIAAAQ+e+D/7da93CcdcG9dcFJVsOI1XCMBaMWHGLBuAUnWA0zVkO8BbMW'
      'vJwF8xZEW7DCgmAL1ljwWhassuBLtWCdBX9Taod1tcOXWjusqh1eq3ZYUzsE1w4raofo'
      '2mG+dni52mG2doivvWGm9oYTaofx2uGQ2mG0djim9oaR2htOqv2C+9ovOK72e/hzY43A'
      'OdYHRqwPnGA1zFgN4dYFs9YFuVbDGqsh02pYZzUEWrDWgjSrYbXVEGXBDguCLNhjQYrV'
      'sMtqiLBgpwUBFuy1YLsFuy3YbMF+Cx7dggQLNlqQYcE2C1IseGgLcizYYkGSBQ9sQZYF'
      'j2tBmgVflgV5FjyqBYkW/KAsyLTgVwIA',
];

/// The development delegates with a picture, by handle.
const _developmentPictureOf = {'alice_votes': 0, 'chidi_node': 1, 'freya_z': 0};

const _developmentProposals = [
  VotingProposalView(
    id: 1,
    title: 'Raise the default fee for shielded transactions',
    description: '',
    options: [
      VotingOptionView(index: 0, label: 'Yes'),
      VotingOptionView(index: 1, label: 'No'),
    ],
  ),
  VotingProposalView(
    id: 2,
    title: 'Fund the wallet usability grant',
    description: '',
    options: [
      VotingOptionView(index: 0, label: 'Fund in full'),
      VotingOptionView(index: 1, label: 'Fund half'),
      VotingOptionView(index: 2, label: "Don't fund"),
    ],
  ),
  VotingProposalView(
    id: 3,
    title: 'Adopt the new governance calendar',
    description: '',
    options: [
      VotingOptionView(index: 0, label: 'Yes'),
      VotingOptionView(index: 1, label: 'No'),
    ],
  ),
];
