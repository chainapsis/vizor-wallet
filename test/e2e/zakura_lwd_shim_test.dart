import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;
import 'package:zcash_wallet/src/generated/service.pbgrpc.dart' as service_grpc;

import '../../integration_test/support/verified_zakura_genesis.dart';
import '../../integration_test/support/regtest_lightwalletd_proxy.dart';
import '../../integration_test/support/zakura_lightwalletd_shim.dart';

const _runId = '1234567890abcdef1234567890abcdef';
final _hash = '12' * 32;

Map<String, dynamic> _proof(int port) => {
  'schema_version': 1,
  'fixture_run_id': _runId,
  'upstream_port': port,
  'identity': {'run_id': _runId},
  'source': {'publication': 'modeled-not-an-actual-node'},
  'empty_tree_codec': VerifiedZakuraGenesis.emptyTreeCodec,
  'wallet_or_catalog_pass': false,
  'genesis_block': {
    'hash': _hash,
    'height': 0,
    'time': 1296688602,
    'nTx': 1,
    'tx': [
      {
        'version': 1,
        'overwintered': false,
        'blockhash': _hash,
        'height': 0,
        'vin': [
          {'coinbase': '01'},
        ],
        'vShieldedSpend': [],
        'vShieldedOutput': [],
        'vjoinsplit': [],
        'orchard': {'actions': []},
      },
    ],
    'valuePools': [
      for (final pool in ['sapling', 'orchard', 'ironwood'])
        {'id': pool, 'chainValueZat': 0, 'valueDeltaZat': 0},
    ],
  },
  'genesis_node_tree': {
    'hash': _hash,
    'height': 0,
    'time': 1296688602,
    for (final pool in ['sapling', 'orchard', 'ironwood'])
      pool: {'commitments': {}},
  },
  'tree_state': {
    'network': 'regtest',
    'height': '0',
    'hash': _hash,
    'time': 1296688602,
    'saplingTree': '000000',
    'orchardTree': '000000',
    'ironwoodTree': '000000',
  },
};

Future<void> _mode(String path, String value) async {
  final result = await Process.run('chmod', [value, path]);
  expect(result.exitCode, 0);
}

Future<String> _writeProof(File file, Object? value) async {
  if (await file.exists()) await _mode(file.path, '600');
  final bytes = utf8.encode(jsonEncode(value));
  await file.writeAsBytes(bytes, flush: true);
  await _mode(file.path, '400');
  return sha256.convert(bytes).toString();
}

Future<VerifiedZakuraGenesis> _read(File file, String digest, int port) =>
    VerifiedZakuraGenesis.read(
      file.path,
      expectedSha256: digest,
      fixtureRunId: _runId,
      upstreamPort: port,
    );

// Only the exercised RPCs are modeled. The socket/server/channel are real;
// neither this transport nor the synthetic proof is actual fixture evidence.
class _RawFixture extends service_grpc.CompactTxStreamerServiceBase {
  final info = service.LightdInfo(
    chainName: 'test',
    blockHeight: Int64(7),
    estimatedHeight: Int64(9),
    consensusBranchId: 'modeled-branch',
  );
  final tree = service.TreeState(
    network: 'test',
    height: Int64(7),
    hash: '34' * 32,
    time: 1296688609,
    saplingTree: '010203',
    orchardTree: '040506',
    ironwoodTree: '070809',
  );
  final latest = service.BlockID(height: Int64(7), hash: [1, 2, 3]);
  final requests = <service.BlockID>[];

  @override
  Future<service.LightdInfo> getLightdInfo(
    grpc.ServiceCall call,
    service.Empty request,
  ) async => info.deepCopy();

  @override
  Future<service.BlockID> getLatestBlock(
    grpc.ServiceCall call,
    service.ChainSpec request,
  ) async => latest.deepCopy();

  @override
  Future<service.TreeState> getTreeState(
    grpc.ServiceCall call,
    service.BlockID request,
  ) async {
    requests.add(request.deepCopy());
    if (request.height == Int64.ZERO) {
      throw grpc.GrpcError.invalidArgument('modeled raw genesis unsupported');
    }
    return tree.deepCopy();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'unexercised modeled RPC: ${invocation.memberName}',
  );
}

void main() {
  group('verified genesis file', () {
    late Directory root;
    late File file;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('vizor-genesis-reader-');
      root = Directory(await root.resolveSymbolicLinks());
      await _mode(root.path, '700');
      file = File('${root.path}/genesis.json');
    });
    tearDown(() async => root.delete(recursive: true));

    test('reads current host schema without RPC error diagnostics', () async {
      final value = await _read(
        file,
        await _writeProof(file, _proof(39067)),
        39067,
      );
      expect(value.hash, _hash);
      expect(value.fixtureRunId, _runId);
      expect(value.upstreamPort, 39067);
      expect(value.treeState().ironwoodTree, '000000');
      final changed = value.treeState()..hash = 'mutated-copy';
      expect(changed.hash, 'mutated-copy');
      expect(value.treeState().hash, _hash);
    });

    final mutations = <String, void Function(Map<String, dynamic>)>{
      'foreign run': (p) => p['fixture_run_id'] = 'f' * 32,
      'foreign identity': (p) => p['identity']['run_id'] = 'f' * 32,
      'foreign port': (p) => p['upstream_port'] = 39068,
      'bool schema': (p) => p['schema_version'] = true,
      'wallet pass claim': (p) => p['wallet_or_catalog_pass'] = true,
      'wrong codec': (p) => p['empty_tree_codec'] = 'borrowed-frontier',
      'zero hash': (p) => p['tree_state']['hash'] = '0' * 64,
      'wrong network': (p) => p['tree_state']['network'] = 'main',
      'height one': (p) => p['genesis_node_tree']['height'] = 1,
      'bool height': (p) => p['genesis_block']['height'] = false,
      'different tree hash': (p) => p['genesis_node_tree']['hash'] = '34' * 32,
      'different time': (p) => p['genesis_block']['time'] = 1,
      'not coinbase': (p) => p['genesis_block']['tx'][0]['vin'] = [null],
      'wrong transaction version': (p) =>
          p['genesis_block']['tx'][0]['version'] = 5,
      'shielded output': (p) =>
          p['genesis_block']['tx'][0]['vShieldedOutput'] = [{}],
      'Ironwood action': (p) => p['genesis_block']['tx'][0]['ironwood'] = {
        'actions': [{}],
      },
      'Ironwood null': (p) => p['genesis_block']['tx'][0]['ironwood'] = null,
      'nonempty tree': (p) => p['genesis_node_tree']['sapling']['commitments'] =
          {'finalState': '000000'},
      'bool pool value': (p) =>
          p['genesis_block']['valuePools'][0]['chainValueZat'] = false,
      'nonzero pool value': (p) =>
          p['genesis_block']['valuePools'][0]['valueDeltaZat'] = 1,
      'missing pool': (p) => p['genesis_block']['valuePools'].removeLast(),
      'duplicate pool': (p) => p['genesis_block']['valuePools'].add(
        Map<String, dynamic>.from(p['genesis_block']['valuePools'][0]),
      ),
      'copied frontier': (p) => p['tree_state']['orchardTree'] = '010203',
    };
    for (final mutation in mutations.entries) {
      test('rejects ${mutation.key}', () async {
        final proof =
            jsonDecode(jsonEncode(_proof(39067))) as Map<String, dynamic>;
        mutation.value(proof);
        await expectLater(
          _read(file, await _writeProof(file, proof), 39067),
          throwsFormatException,
        );
      });
    }

    test('requires exact digest and expected upstream/run', () async {
      final digest = await _writeProof(file, _proof(39067));
      await expectLater(_read(file, '0' * 64, 39067), throwsFormatException);
      await expectLater(_read(file, digest, 39068), throwsFormatException);
      await expectLater(
        VerifiedZakuraGenesis.read(
          file.path,
          expectedSha256: digest,
          fixtureRunId: 'f' * 32,
          upstreamPort: 39067,
        ),
        throwsFormatException,
      );
    });

    test('rejects writable proof, readable parent and symbolic path', () async {
      final digest = await _writeProof(file, _proof(39067));
      await _mode(file.path, '600');
      await expectLater(_read(file, digest, 39067), throwsFormatException);
      await _mode(file.path, '400');
      await _mode(root.path, '755');
      await expectLater(_read(file, digest, 39067), throwsFormatException);
      await _mode(root.path, '700');
      final link = Link('${root.path}/link.json');
      await link.create(file.path);
      await expectLater(
        _read(File(link.path), digest, 39067),
        throwsFormatException,
      );
    });

    test('rejects oversized handoff before decoding', () async {
      final proof = _proof(39067)
        ..['extra'] = 'x' * VerifiedZakuraGenesis.maxProofBytes;
      await expectLater(
        _read(file, await _writeProof(file, proof), 39067),
        throwsFormatException,
      );
    });
  }, skip: Platform.isWindows);

  group('direct shim RPC boundary', () {
    late Directory root;
    late _RawFixture raw;
    late grpc.Server upstream;
    late ZakuraLightwalletdShim shim;
    late grpc.ClientChannel channel;
    late service_grpc.CompactTxStreamerClient client;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('vizor-shim-transport-');
      root = Directory(await root.resolveSymbolicLinks());
      await _mode(root.path, '700');
      raw = _RawFixture();
      upstream = grpc.Server.create(services: [raw]);
      await upstream.serve(address: InternetAddress.loopbackIPv4, port: 0);
      final port = upstream.port!;
      final file = File('${root.path}/genesis.json');
      final genesis = await _read(
        file,
        await _writeProof(file, _proof(port)),
        port,
      );
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final listenPort = reservation.port;
      await reservation.close();
      shim = ZakuraLightwalletdShim(
        listenPort: listenPort,
        targetPort: port,
        genesis: genesis,
      );
      await shim.start();
      channel = grpc.ClientChannel(
        '127.0.0.1',
        port: listenPort,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      );
      client = service_grpc.CompactTxStreamerClient(
        channel,
        options: grpc.CallOptions(timeout: const Duration(seconds: 3)),
      );
    });
    tearDown(() async {
      await shim.stop();
      await channel.shutdown();
      await upstream.shutdown();
      await root.delete(recursive: true);
    });

    test(
      'serves only node-verified genesis, never the zero-hash fault stub',
      () async {
        shim.serveEmptyGenesisTreeState();
        final value = await client.getTreeState(
          service.BlockID(height: Int64.ZERO),
        );
        expect(value.writeToBuffer(), shim.genesis.treeState().writeToBuffer());
        expect(raw.requests, isEmpty);
        shim.setDown();
        await expectLater(
          client.getTreeState(service.BlockID(height: Int64.ZERO)),
          throwsA(
            isA<grpc.GrpcError>().having(
              (e) => e.code,
              'code',
              grpc.StatusCode.unavailable,
            ),
          ),
        );
        shim.setHealthy();
        expect((await client.getTreeState(service.BlockID())).hash, _hash);
      },
    );

    test(
      'nonzero TreeState and other RPCs preserve serialized upstream fields',
      () async {
        final request = service.BlockID(height: Int64(7), hash: [4, 5, 6]);
        final value = await client.getTreeState(request);
        expect(value.writeToBuffer(), raw.tree.writeToBuffer());
        expect(raw.requests.single.writeToBuffer(), request.writeToBuffer());
        expect(
          (await client.getLatestBlock(service.ChainSpec())).writeToBuffer(),
          raw.latest.writeToBuffer(),
        );
      },
    );

    test('hash-qualified genesis is forwarded, not substituted', () async {
      final request = service.BlockID(
        height: Int64.ZERO,
        hash: List.filled(32, 0x12),
      );
      await expectLater(
        client.getTreeState(request),
        throwsA(
          isA<grpc.GrpcError>().having(
            (e) => e.code,
            'code',
            grpc.StatusCode.invalidArgument,
          ),
        ),
      );
      expect(raw.requests.single.writeToBuffer(), request.writeToBuffer());
    });

    test('LightdInfo normalizes only test/regtest chainName', () async {
      final expected = raw.info.deepCopy()..chainName = 'regtest';
      expect(
        (await client.getLightdInfo(service.Empty())).writeToBuffer(),
        expected.writeToBuffer(),
      );
      raw.info.chainName = 'regtest';
      expect(
        (await client.getLightdInfo(service.Empty())).writeToBuffer(),
        raw.info.writeToBuffer(),
      );
      raw.info.chainName = 'main';
      await expectLater(
        client.getLightdInfo(service.Empty()),
        throwsA(
          isA<grpc.GrpcError>().having(
            (e) => e.code,
            'code',
            grpc.StatusCode.failedPrecondition,
          ),
        ),
      );
    });

    test(
      'constructor rejects raw-port mismatch, equal ports and invalid ports',
      () {
        for (final ports in [
          [0, upstream.port!],
          [shim.listenPort, 0],
          [upstream.port!, upstream.port!],
          [shim.listenPort, 65536],
        ]) {
          expect(
            () => ZakuraLightwalletdShim(
              listenPort: ports[0],
              targetPort: ports[1],
              genesis: shim.genesis,
            ),
            throwsArgumentError,
          );
        }
      },
    );
    test('ordinary proxy retains its explicit fault-stub behavior', () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final proxy = RegtestLightwalletdProxy(
        listenPort: port,
        targetPort: upstream.port!,
      );
      final directChannel = grpc.ClientChannel(
        '127.0.0.1',
        port: port,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      );
      final directClient = service_grpc.CompactTxStreamerClient(
        directChannel,
        options: grpc.CallOptions(timeout: const Duration(seconds: 3)),
      );
      try {
        await proxy.start();
        await expectLater(
          directClient.getTreeState(service.BlockID()),
          throwsA(
            isA<grpc.GrpcError>().having(
              (e) => e.code,
              'code',
              grpc.StatusCode.invalidArgument,
            ),
          ),
        );
        proxy.serveEmptyGenesisTreeState();
        expect(
          (await directClient.getTreeState(service.BlockID())).hash,
          '0' * 64,
        );
        proxy.setDown();
        await expectLater(
          directClient.getTreeState(service.BlockID()),
          throwsA(
            isA<grpc.GrpcError>().having(
              (e) => e.code,
              'code',
              grpc.StatusCode.unavailable,
            ),
          ),
        );
      } finally {
        await proxy.stop();
        await directChannel.shutdown();
      }
    });
  }, skip: Platform.isWindows);
}
