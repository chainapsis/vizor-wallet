import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;
import 'package:zcash_wallet/src/generated/service.pbgrpc.dart' as service_grpc;

class AcceptingLightwalletd extends service_grpc.CompactTxStreamerServiceBase {
  AcceptingLightwalletd({this.chainHeight = 1});

  final int chainHeight;
  grpc.Server? _server;
  int sendTransactionCount = 0;
  List<int> lastRawTransaction = const [];

  String get url {
    final port = _server?.port;
    if (port == null) throw StateError('Test lightwalletd is not running.');
    return 'http://127.0.0.1:$port';
  }

  Future<void> start() async {
    _server = grpc.Server.create(services: [this]);
    await _server!.serve(address: InternetAddress.loopbackIPv4, port: 0);
  }

  Future<void> stop() async {
    await _server?.shutdown();
    _server = null;
  }

  @override
  Future<service.BlockID> getLatestBlock(
    grpc.ServiceCall call,
    service.ChainSpec request,
  ) async {
    return service.BlockID(height: Int64(chainHeight));
  }

  @override
  Future<service.SendResponse> sendTransaction(
    grpc.ServiceCall call,
    service.RawTransaction request,
  ) async {
    sendTransactionCount++;
    lastRawTransaction = List<int>.unmodifiable(request.data);
    return service.SendResponse(errorCode: 0, errorMessage: '');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
