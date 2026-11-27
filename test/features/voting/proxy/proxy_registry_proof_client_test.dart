import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_proof_client.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegation.dart' as rust;

import 'support/proxy_registry_proof_fakes.dart';
import 'support/proxy_rust_fake.dart';

void main() {
  useProxyRustFake();
  final a = Uri.parse('https://proof-a.example');
  final b = Uri.parse('https://proof-b.example');

  /// A client over [hosts] with [bridge] as Rust's reader, and retries
  /// that do not wait.
  ProxyRegistryProofClient client(
    FakeProofHosts hosts,
    FakeRegistryProofRust bridge, {
    DateTime Function()? clock,
  }) {
    proxyRust.proofs = bridge;
    return ProxyRegistryProofClient(
      hosts,
      clock: clock ?? () => DateTime.utc(2026, 10, 7),
      delay: (_) async {},
    );
  }

  /// Expects [future] to end in the one cannot-verify outcome.
  Future<void> expectCannotVerify(Future<Object?> future) => expectLater(
    future,
    throwsA(
      isA<ProxyDelegationError>().having(
        (error) => error.kind,
        'kind',
        ProxyDelegationErrorKind.cannotVerify,
      ),
    ),
  );

  test('proves the chosen entries from the first host, in order', () async {
    final hosts = FakeProofHosts();
    final bridge = FakeRegistryProofRust();

    final entries = await client(
      hosts,
      bridge,
    ).prove(network: 'main', proofRpcUrls: [a, b], delegateIndices: [17, 4]);

    expect([for (final entry in entries) entry.delegateIndex], [17, 4]);
    expect(
      [for (final entry in entries) entry.entry],
      [
        [8, 17],
        null,
      ],
    );
    expect(hosts.requests.map((uri) => uri.host).toSet(), {a.host});
    expect(hosts.requests.map((uri) => uri.path), [
      '/commit',
      '/validators',
      '/abci_query',
      '/abci_query',
    ]);
    expect(hosts.requests[1].queryParameters, {
      'height': '101',
      'per_page': '100',
    });
    expect(hosts.requests[2].queryParameters, {
      'path': '"/store/vote/key"',
      'data': '0x1a0100000011',
      'height': '100',
      'prove': 'true',
    });
    expect(
      hosts.timeouts,
      everyElement(ProxyRegistryProofClient.requestTimeout),
    );
    final evidence = bridge.verified.single;
    expect(evidence.network, 'main');
    expect(evidence.delegateIndices, [17, 4]);
    expect(
      [
        for (final query in evidence.json['queries'] as List)
          ((query as Map)['result'] as Map)['response']['key'],
      ],
      ['0x1a0100000011', '0x1a0100000004'],
    );
  });

  test('fails over on transport errors after one retry', () async {
    for (final error in <Object>[
      const SocketException('refused'),
      TimeoutException('slow'),
      const HttpException('reset'),
    ]) {
      final hosts = FakeProofHosts(failing: {a.host: error});
      final bridge = FakeRegistryProofRust();

      await client(
        hosts,
        bridge,
      ).prove(network: 'main', proofRpcUrls: [a, b], delegateIndices: [1]);

      expect(
        hosts.requests.where((uri) => uri.host == a.host).length,
        2,
        reason: '$error is retried once on the same host',
      );
      expect(bridge.verifiedHosts, [b.host]);
    }
  });

  test('fails over on transient answers after one retry', () async {
    for (final status in [429, 500, 502, 503, 504]) {
      final hosts = FakeProofHosts(statuses: {a.host: status});
      final bridge = FakeRegistryProofRust();

      await client(
        hosts,
        bridge,
      ).prove(network: 'main', proofRpcUrls: [a, b], delegateIndices: [1]);

      expect(hosts.requests.where((uri) => uri.host == a.host).length, 2);
      expect(bridge.verifiedHosts, [b.host]);
    }
  });

  test('fails over on invalid evidence and other answers', () async {
    final rejecting = FakeRegistryProofRust()..rejectedHosts.add(a.host);
    final first = FakeProofHosts();
    await client(
      first,
      rejecting,
    ).prove(network: 'main', proofRpcUrls: [a, b], delegateIndices: [1]);
    expect(rejecting.verifiedHosts, [a.host, b.host]);

    for (final hosts in [
      FakeProofHosts(statuses: {a.host: 404}),
      FakeProofHosts(oversized: {a.host}),
      FakeProofHosts(heights: {a.host: 1}),
    ]) {
      final bridge = FakeRegistryProofRust();
      await client(
        hosts,
        bridge,
      ).prove(network: 'main', proofRpcUrls: [a, b], delegateIndices: [1]);
      expect(bridge.verifiedHosts, [b.host]);
    }
  });

  test('every failure becomes one cannot-verify outcome', () async {
    final c = Uri.parse('https://proof-c.example');
    final hosts = FakeProofHosts(
      statuses: {a.host: 404},
      failing: {c.host: const SocketException('refused')},
    );
    final bridge = FakeRegistryProofRust()..rejectedHosts.add(b.host);

    final failure = client(
      hosts,
      bridge,
    ).prove(network: 'main', proofRpcUrls: [a, b, c], delegateIndices: [1]);

    await expectCannotVerify(failure);
    final error = await failure.then<Object?>((_) => null, onError: (e) => e);
    expect(error.toString(), isNot(contains('proof-')));
    expect(error.toString(), isNot(contains('1a01')));
    expect(
      {for (final uri in hosts.requests) uri.host},
      {a.host, b.host, c.host},
    );

    await expectCannotVerify(
      client(
        FakeProofHosts(),
        FakeRegistryProofRust(),
      ).prove(network: 'main', proofRpcUrls: const [], delegateIndices: [1]),
    );
  });

  test('refused indices fail before any request', () async {
    final hosts = FakeProofHosts();
    final bridge = FakeRegistryProofRust()..refuseIndices = true;

    await expectCannotVerify(
      client(
        hosts,
        bridge,
      ).prove(network: 'main', proofRpcUrls: [a], delegateIndices: [0]),
    );
    expect(hosts.requests, isEmpty);
  });

  test('no choice needs no request', () async {
    final hosts = FakeProofHosts();
    final bridge = FakeRegistryProofRust();

    expect(
      await client(
        hosts,
        bridge,
      ).prove(network: 'main', proofRpcUrls: [a], delegateIndices: const []),
      isEmpty,
    );
    expect(hosts.requests, isEmpty);
    expect(bridge.verified, isEmpty);
  });

  test('only HTTPS hosts serve proofs, or loopback HTTP on regtest', () async {
    final plain = Uri.parse('http://proof-a.example');
    final credentialed = Uri.parse('https://user@proof-a.example');
    final loopback = Uri.parse('http://127.0.0.1:26657');
    final hosts = FakeProofHosts();
    final bridge = FakeRegistryProofRust();

    await expectCannotVerify(
      client(hosts, bridge).prove(
        network: 'main',
        proofRpcUrls: [plain, credentialed, loopback],
        delegateIndices: [1],
      ),
    );
    expect(hosts.requests, isEmpty);

    await client(hosts, bridge).prove(
      network: 'regtest',
      proofRpcUrls: [plain, loopback],
      delegateIndices: [1],
    );
    expect({for (final uri in hosts.requests) uri.host}, {'127.0.0.1'});
  });

  test('keeps a host path prefix', () async {
    final hosts = FakeProofHosts();
    await client(hosts, FakeRegistryProofRust()).prove(
      network: 'main',
      proofRpcUrls: [Uri.parse('https://rpc.example/cometbft/')],
      delegateIndices: [1],
    );
    expect(hosts.requests.first.path, '/cometbft/commit');
    expect(hosts.requests.last.path, '/cometbft/abci_query');
  });

  test('stops trying hosts at the deadline', () async {
    var now = DateTime.utc(2026, 10, 7);
    final hosts = FakeProofHosts(
      statuses: {a.host: 404},
      onRequest: () => now = now.add(const Duration(minutes: 3)),
    );
    final bridge = FakeRegistryProofRust();

    await expectCannotVerify(
      client(
        hosts,
        bridge,
        clock: () => now,
      ).prove(network: 'main', proofRpcUrls: [a, b], delegateIndices: [1]),
    );
    expect({for (final uri in hosts.requests) uri.host}, {a.host});
  });

  test('a request never outlasts the remaining deadline', () async {
    var now = DateTime.utc(2026, 10, 7);
    final hosts = FakeProofHosts(
      onRequest: () => now = now.add(const Duration(seconds: 115)),
    );

    await expectCannotVerify(
      client(
        hosts,
        FakeRegistryProofRust(),
        clock: () => now,
      ).prove(network: 'main', proofRpcUrls: [a], delegateIndices: [1]),
    );
    expect(hosts.timeouts.first, ProxyRegistryProofClient.requestTimeout);
    expect(hosts.timeouts[1], const Duration(seconds: 5));
  });

  test('proven entries keep the bytes Rust returned', () async {
    final bridge = FakeRegistryProofRust()
      ..entries = {
        9: Uint8List.fromList([1, 2, 3]),
      };
    final entries = await client(
      FakeProofHosts(),
      bridge,
    ).prove(network: 'test', proofRpcUrls: [a], delegateIndices: [9]);
    expect(entries.single, isA<rust.ApiProvenRegistryEntry>());
    expect(entries.single.entry, [1, 2, 3]);
    expect(bridge.verified.single.network, 'test');
  });

  group('raw store values', () {
    const key = '0b0101';

    test('reads the first host that answers, unproven', () async {
      final hosts = FakeProofHosts(
        failing: {a.host: const SocketException('down')},
        storeValues: {
          '0x$key': Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 37]),
        },
      );
      final value = await client(
        hosts,
        FakeRegistryProofRust(),
      ).storeValue(network: 'main', proofRpcUrls: [a, b], keyHex: key);
      expect(value, [0, 0, 0, 0, 0, 0, 0, 37]);
      expect(hosts.requests.last.host, b.host);
      expect(hosts.requests.last.path, '/abci_query');
      expect(hosts.requests.last.queryParameters, {
        'path': '"/store/vote/key"',
        'data': '0x$key',
      });
    });

    test('an absent key is null and no answer is an error', () async {
      final bridge = FakeRegistryProofRust();
      expect(
        await client(
          FakeProofHosts(),
          bridge,
        ).storeValue(network: 'main', proofRpcUrls: [a], keyHex: key),
        isNull,
      );
      await expectLater(
        client(
          FakeProofHosts(statuses: {a.host: 500, b.host: 404}),
          bridge,
        ).storeValue(network: 'main', proofRpcUrls: [a, b], keyHex: key),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        client(FakeProofHosts(), bridge).storeValue(
          network: 'main',
          proofRpcUrls: [Uri.parse('http://proof-a.example')],
          keyHex: key,
        ),
        throwsA(isA<StateError>()),
        reason: 'plain HTTP is never used off regtest',
      );
    });
  });
}
