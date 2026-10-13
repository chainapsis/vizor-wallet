import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;

import 'regtest_lightwalletd_proxy.dart';
import 'verified_zakura_genesis.dart';

/// Direct-fixture adaptation; all non-genesis TreeStates remain raw upstream.
final class ZakuraLightwalletdShim extends RegtestLightwalletdProxy {
  factory ZakuraLightwalletdShim({
    required int listenPort,
    required int targetPort,
    required VerifiedZakuraGenesis genesis,
    void Function(String message)? log,
  }) {
    if (listenPort < 1 ||
        listenPort > 65535 ||
        targetPort < 1 ||
        targetPort > 65535 ||
        listenPort == targetPort ||
        genesis.upstreamPort != targetPort) {
      throw ArgumentError('shim ports must match the verified raw upstream');
    }
    return ZakuraLightwalletdShim._(
      listenPort: listenPort,
      targetPort: targetPort,
      genesis: genesis,
      log: log,
    );
  }

  ZakuraLightwalletdShim._({
    required super.listenPort,
    required super.targetPort,
    required this.genesis,
    super.log,
  });

  final VerifiedZakuraGenesis genesis;

  @override
  service.TreeState? localTreeState(service.BlockID request) =>
      request.height == Int64.ZERO && request.hash.isEmpty
      ? genesis.treeState()
      : null;

  @override
  Future<service.LightdInfo> getLightdInfo(
    grpc.ServiceCall call,
    service.Empty request,
  ) async {
    final info = await super.getLightdInfo(call, request);
    if (info.chainName != 'test' && info.chainName != 'regtest') {
      throw grpc.GrpcError.failedPrecondition(
        'raw fixture is not test/regtest',
      );
    }
    return info.deepCopy()..chainName = 'regtest';
  }
}
