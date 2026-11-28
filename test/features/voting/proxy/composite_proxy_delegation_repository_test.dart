import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/composite_proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegator_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_fetcher.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_proof_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_store.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_service_sources.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_file_cache.dart';

import 'support/proxy_delegator_fakes.dart';
import 'support/proxy_registry_fakes.dart';
import 'support/proxy_registry_proof_fakes.dart';
import 'support/proxy_rust_fake.dart';

/// A registry client whose pre-proving check answers [verdicts] without
/// fetching anything.
class _CheckingRegistryClient extends ProxyRegistryClient {
  _CheckingRegistryClient()
    : super(
        network: 'main',
        sources: ProxyServiceSources(),
        store: ProxyRegistryStore(
          VotingFileCache(directory: () async => throw UnimplementedError()),
        ),
        fetcher: ProxyRegistryFetcher(FakeProofHosts()),
        proofs: ProxyRegistryProofClient(FakeProofHosts()),
        chainGet: (_) async => VotingChainAnswer(503, Uint8List(0)),
        firstNewIndex: (_) async => null,
        beginWork: () => () {},
      );

  /// The verdicts the next check gives.
  List<DelegateCheck> verdicts = const [];

  /// How often the check ran.
  int checks = 0;

  @override
  Future<List<ApiConfirmedDelegate>> check(
    String roundId,
    List<ProxyDelegateChoice> choices,
  ) async {
    checks++;
    return [
      for (final verdict in verdicts) ApiConfirmedDelegate(check: verdict),
    ];
  }
}

void main() {
  useProxyRustFake();
  late _CheckingRegistryClient registry;
  late FakeProxyDelegatorRust bridge;
  late CompositeProxyDelegationRepository repository;
  setUp(() {
    registry = _CheckingRegistryClient();
    bridge = proxyRust.delegator = FakeProxyDelegatorRust();
    repository = CompositeProxyDelegationRepository(
      registry: registry,
      delegator: ProxyDelegatorClient(
        host: FakeProxyDelegatorHost(FakeProxyDelegatorChain()),
        clock: () => DateTime.utc(2026, 10, 7, 12),
      ),
    );
  });

  /// A request to delegates 3 and 4, a quarter each.
  ProxyAllocationRequest request() => ProxyAllocationRequest(
    roundId: kRegistryTestRoundId,
    choices: [
      for (final index in const [3, 4])
        ProxyDelegateChoice(
          delegateIndex: index,
          percentBps: 2500,
          provider: ProxyDelegateProvider.x,
          handle: 'delegate$index',
          dk: 'zvdk1key$index',
        ),
    ],
  );

  group('commit', () {
    test('proves the delegates again and commits with that check', () async {
      registry.verdicts = [DelegateCheck.ok, DelegateCheck.ok];
      final preview = await repository.preview(request());

      await repository.commit(request(), confirmed: preview);

      expect(bridge.committed!.checks, [DelegateCheck.ok, DelegateCheck.ok]);
      expect(registry.checks, 1, reason: 'the commit proves them itself');
    });

    for (final verdict in DelegateCheck.values) {
      if (verdict == DelegateCheck.ok) continue;
      test('a delegate the check finds ${verdict.name} commits nothing and '
          'sends the review back to its check', () async {
        registry.verdicts = [DelegateCheck.ok, verdict];
        final preview = await repository.preview(request());

        await expectLater(
          repository.commit(request(), confirmed: preview),
          throwsA(isA<ProxyReviewChangedException>()),
        );
        expect(bridge.committed, isNull);
      });
    }
  });
}
