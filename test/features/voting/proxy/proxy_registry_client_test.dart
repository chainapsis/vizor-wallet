import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_fetcher.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_proof_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_store.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_service_sources.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_file_cache.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

import 'support/proxy_registry_fakes.dart';
import 'support/proxy_registry_proof_fakes.dart';
import 'support/proxy_rust_fake.dart';

/// The device time.
final _now = DateTime.fromMillisecondsSinceEpoch(1790259200 * 1000);

/// The two wallet list mirrors the build names.
const _listA = 'https://lists-a.example/prod/wallets/vizor/list.json';
const _listB = 'https://lists-b.example/prod/wallets/vizor/list.json';

/// Registry mirrors answering from a URL map, recording each request.
class _Mirrors implements VotingHttpClient {
  /// The answer per URL: bytes, a status code, or an error to throw.
  final answers = <String, Object>{};

  /// Every request, in order.
  final requests = <String>[];

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async {
    requests.add(uri.toString());
    final answer = answers[uri.toString()];
    if (answer is Uint8List) {
      return VotingHttpResponse(statusCode: 200, bodyBytes: answer);
    }
    if (answer is int) {
      return VotingHttpResponse(statusCode: answer, bodyBytes: Uint8List(0));
    }
    throw answer ?? const SocketException('no route to mirror');
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration? timeout,
    int? maxBodyBytes,
  }) => throw UnsupportedError('Registry mirrors are only read');
}

void main() {
  useProxyRustFake();
  late Directory root;
  late ProxyRegistryStore store;
  late FakeProxyRegistryRust bridge;
  late VotingShareTrackingRegistry drain;
  late ProxyServiceSources sources;
  late _Mirrors mirrors;
  late FakeProofHosts proofHosts;
  late FakeRegistryProofRust proofBridge;
  late Map<int, VotingChainAnswer> pages;
  late List<String> chainPaths;
  late DateTime now;

  final alicePicture = utf8.encode('alice webp');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('proxy-registry-client-');
    store = ProxyRegistryStore(VotingFileCache(directory: () async => root));
    bridge = proxyRust.registry = FakeProxyRegistryRust()
      ..listings.addAll({
        17: FakeListing(17, 'alice', name: 'Alice', picture: alicePicture),
        18: FakeListing(18, 'bob'),
        19: FakeListing(19, 'carol'),
        21: FakeListing(
          21,
          'dave',
          status: rust_wire.DelegateEntryStatus.retired,
        ),
      });
    drain = VotingShareTrackingRegistry();
    sources = ProxyServiceSources();
    await sources.ingest(
      fakeConfigFetch([
        fakeDynamicConfig(
          proofRpcUrls: ['https://rpc-a.example', 'https://rpc-b.example'],
        ),
      ]),
      network: 'main',
    );
    mirrors = _Mirrors()
      ..answers.addAll({
        _listA: fakeWalletList(2, rows: [17, 18], signed: false),
        _listB: fakeWalletList(1, rows: [17, 18]),
      });
    proofHosts = FakeProofHosts();
    proofBridge = proxyRust.proofs = FakeRegistryProofRust();
    pages = {
      0: VotingChainAnswer(200, fakeRegistryPage([17, 18], next: 18)),
      18: VotingChainAnswer(200, fakeRegistryPage([19, 21])),
    };
    chainPaths = [];
    now = _now;
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// The client under test on [network], with [builtInProofHost] as Vizor's
  /// own host.
  ProxyRegistryClient client({
    Uri? builtInProofHost,
    String network = 'main',
    ({String keyId, String publicKey})? regtestKey,
  }) => ProxyRegistryClient(
    network: network,
    sources: sources,
    store: store,
    fetcher: ProxyRegistryFetcher(mirrors),
    proofs: ProxyRegistryProofClient(
      proofHosts,
      clock: () => now,
      delay: (_) async {},
    ),
    chainGet: (path) async {
      chainPaths.add(path);
      final startAfter = int.parse(
        Uri.parse(path).queryParameters['start_after']!,
      );
      return pages[startAfter] ?? VotingChainAnswer(503, Uint8List(0));
    },
    firstNewIndex: (_) async => 18,
    beginWork: drain.beginBackgroundWork,
    builtInProofHost: builtInProofHost,
    walletListUrls: const [_listA, _listB],
    regtestWalletListKey: regtestKey,
    clock: () => now,
  );

  group('browse', () {
    test('downloads the whole registry page by page, keeps the newest '
        'signed list, and shows its rows in list order', () async {
      final browse = await client().browse(kRegistryTestRoundId);

      expect(chainPaths, [
        bridge.registryPagePath(0),
        bridge.registryPagePath(18),
      ]);
      expect(browse.listed.map((entry) => entry.index), [17, 18]);
      expect(browse.listUnavailable, isFalse);
      expect(mirrors.requests, [
        _listA,
        _listB,
      ], reason: 'an unsigned list is passed over like a down mirror');
      expect(await store.readWalletList('main'), mirrors.answers[_listB]);
      expect(jsonDecode((await store.readRegistryCache('main'))!)['entries'], [
        17,
        18,
        19,
        21,
      ]);
    });

    test('a later browse within the max ages fetches nothing, and a lower '
        'version never replaces the stored list', () async {
      final registry = client();
      await registry.browse(kRegistryTestRoundId);
      mirrors.requests.clear();
      chainPaths.clear();
      await registry.browse(kRegistryTestRoundId);
      expect(mirrors.requests, isEmpty);
      expect(chainPaths, isEmpty);

      now = now.add(const Duration(hours: 2));
      mirrors.answers[_listA] = fakeWalletList(3, rows: [18]);
      final newer = await registry.browse(kRegistryTestRoundId);
      expect(newer.listed.map((entry) => entry.index), [18]);
      expect(chainPaths, isNotEmpty, reason: 'the cache was stale too');

      now = now.add(const Duration(hours: 2));
      mirrors.answers[_listA] = fakeWalletList(2, rows: [17]);
      mirrors.answers[_listB] = fakeWalletList(2, rows: [17]);
      final kept = await registry.browse(kRegistryTestRoundId);
      expect(kept.listed.map((entry) => entry.index), [18]);
    });

    test('an unchanged or older first mirror passes over to a newer '
        'second one', () async {
      final registry = client();
      mirrors.answers[_listA] = fakeWalletList(3, rows: [17]);
      await registry.browse(kRegistryTestRoundId);
      // The stored list is version 3, then 4.
      for (final (stale, first, second) in [
        ('unchanged', 3, 4),
        ('older', 2, 5),
      ]) {
        now = now.add(const Duration(hours: 2));
        mirrors.answers[_listA] = fakeWalletList(first, rows: [17]);
        mirrors.answers[_listB] = fakeWalletList(second, rows: [18]);
        mirrors.requests.clear();
        final browse = await registry.browse(kRegistryTestRoundId);
        expect(mirrors.requests, [_listA, _listB], reason: stale);
        expect(browse.listed.map((entry) => entry.index), [18], reason: stale);
      }
    });

    test('a failed download keeps the stored cache, and without one browse '
        'fails', () async {
      final registry = client();
      await registry.browse(kRegistryTestRoundId);
      now = now.add(const Duration(hours: 2));
      pages[18] = VotingChainAnswer(503, Uint8List(0));
      final browse = await registry.browse(kRegistryTestRoundId);
      expect(browse.listed.map((entry) => entry.index), [17, 18]);

      await store.clear();
      await expectLater(
        client().browse(kRegistryTestRoundId),
        throwsA(isA<ProxyDelegationError>()),
      );
    });

    test('a regtest client hands the harness key to Rust once', () async {
      final registry = client(
        network: 'regtest',
        regtestKey: (keyId: 'vizor-regtest', publicKey: 'AAAA'),
      );
      for (var i = 0; i < 2; i++) {
        await registry.listPicture(17);
        now = now.add(const Duration(hours: 2));
      }
      expect(bridge.regtestKeys, ['vizor-regtest:AAAA']);
      await client(regtestKey: (keyId: 'k', publicKey: 'p')).listPicture(17);
      expect(bridge.regtestKeys, hasLength(1), reason: 'mainnet ignores it');
    });
  });

  group('paste or scan', () {
    test('finds an entry in the cache without a proof', () async {
      final found = await client().lookup(kRegistryTestRoundId, '#19');
      expect(found.kind, ApiDelegateLookupKind.found);
      expect((found.listing!.index, found.listing!.handle), (19, 'carol'));
      expect(proofBridge.verified, isEmpty);
      expect(proofHosts.requests, isEmpty);
    });
  });

  group('confirm', () {
    const alice = ProxyDelegateChoice(
      delegateIndex: 17,
      percentBps: 5000,
      provider: ProxyDelegateProvider.x,
      handle: 'alice',
      dk: 'zvdk1fake17',
    );
    const carol = ProxyDelegateChoice(
      delegateIndex: 19,
      percentBps: 2500,
      provider: ProxyDelegateProvider.x,
      handle: 'carol',
      dk: 'zvdk1fake19',
    );

    test('proves every chosen entry in one evidence answer and returns the '
        'proven delegates', () async {
      final confirmed = await client().check(kRegistryTestRoundId, [
        alice,
        carol,
      ]);

      expect(proofBridge.verified.single.delegateIndices, [17, 19]);
      expect(
        [for (final delegate in confirmed) delegate.check],
        [DelegateCheck.ok, DelegateCheck.ok],
      );
      expect(confirmed.first.listing?.reviewed, isTrue);
      expect(confirmed.last.listing?.newThisRound, isTrue);
      final check = bridge.checked.single;
      expect(check.firstNewIndex, 18);
      expect(
        [
          for (final choice in check.request.choices)
            (choice.delegateIndex, choice.handle, choice.dk, choice.provider),
        ],
        [
          (17, 'alice', 'zvdk1fake17', rust_wire.ProxyDelegateProvider.x),
          (19, 'carol', 'zvdk1fake19', rust_wire.ProxyDelegateProvider.x),
        ],
      );
    });

    test('no proof host that verifies means it cannot verify', () async {
      proofBridge.rejectedHosts.addAll(['rpc-a.example', 'rpc-b.example']);
      await expectLater(
        client().check(kRegistryTestRoundId, [alice, carol]),
        throwsA(
          isA<ProxyDelegationError>().having(
            (error) => error.kind,
            'kind',
            ProxyDelegationErrorKind.cannotVerify,
          ),
        ),
      );
      expect(bridge.checked, isEmpty);
    });
  });

  group('delegate mode', () {
    test('proves entries and reads raw store values on the proof hosts, '
        'then Vizor\'s own', () async {
      final own = Uri.parse('https://vizor-rpc.example');
      proofHosts = FakeProofHosts(
        failing: {
          'rpc-a.example': const SocketException('down'),
          'rpc-b.example': const SocketException('down'),
        },
        storeValues: {
          '0x0b17': Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 5]),
        },
      );
      final registry = client(builtInProofHost: own);
      final proven = await registry.proveEntries([17]);
      expect(proven.single.delegateIndex, 17);
      expect(proven.single.entry, [8, 17]);
      expect(proofBridge.verifiedHosts, [own.host]);
      expect(await registry.storeValue('0b17'), [0, 0, 0, 0, 0, 0, 0, 5]);
      expect(proofHosts.requests.last.host, own.host);
    });

    test('reads the list picture', () async {
      final registry = client();
      expect((await registry.listPicture(17))?.webp, alicePicture);
      expect(await registry.listPicture(19), isNull);
    });
  });

  group('round facts', () {
    test('read the proxy state from the vote server\'s round JSON', () {
      expect(
        proxyNextDelegateIndexAtCreation({
          'proxy_delegation': {
            'enabled': true,
            'next_delegate_index_at_creation': 7,
          },
        }),
        7,
      );
      expect(
        proxyNextDelegateIndexAtCreation({
          'round': {
            'proxy_delegation': {'next_delegate_index_at_creation': '9'},
          },
        }),
        9,
      );
      expect(proxyNextDelegateIndexAtCreation(const {}), isNull);
      expect(
        proxyRoundEnabled({
          'proxy_delegation': {'enabled': true},
        }),
        isTrue,
      );
      expect(proxyRoundEnabled(const {}), isFalse);
    });
  });

  test('nothing is fetched or written while deletion holds the voting '
      'data', () async {
    final draining = drain.quiesceAndDrain(accountUuid: 'account-1');
    await expectLater(
      client().browse(kRegistryTestRoundId),
      throwsA(isA<ProxyDelegationError>()),
    );
    await draining;
    expect(mirrors.requests, isEmpty);
    expect(chainPaths, isEmpty);
    expect(await store.readRegistryCache('main'), isNull);
    drain.resume(accountUuid: 'account-1');
  });
}
