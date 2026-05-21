import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:zcash_wallet/src/generated/compact_formats.pb.dart' as compact;
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;
import 'package:zcash_wallet/src/generated/service.pbgrpc.dart' as service_grpc;

enum _ProxyMode { healthy, slowHeight, down }

class RegtestLightwalletdProxy
    extends service_grpc.CompactTxStreamerServiceBase {
  RegtestLightwalletdProxy({
    this.listenPort = 19068,
    this.targetPort = 9067,
    void Function(String message)? log,
  }) : _log = log ?? ((_) {}),
       _channel = grpc.ClientChannel(
         '127.0.0.1',
         port: targetPort,
         options: const grpc.ChannelOptions(
           credentials: grpc.ChannelCredentials.insecure(),
         ),
       ) {
    _client = service_grpc.CompactTxStreamerClient(_channel);
  }

  final int listenPort;
  final int targetPort;
  final void Function(String message) _log;
  final grpc.ClientChannel _channel;
  late final service_grpc.CompactTxStreamerClient _client;
  grpc.Server? _server;
  _ProxyMode _mode = _ProxyMode.healthy;
  int? _slowHeight;
  int _sendTransactionFailuresRemaining = 0;
  int _failedSendTransactionCount = 0;

  String get url => 'http://127.0.0.1:$listenPort';
  int get failedSendTransactionCount => _failedSendTransactionCount;

  Future<void> start() async {
    _server = grpc.Server.create(services: [this]);
    await _server!.serve(
      address: InternetAddress.loopbackIPv4,
      port: listenPort,
    );
    _log('primary proxy listening on $url');
  }

  Future<void> stop() async {
    await _server?.shutdown();
    await _channel.shutdown();
  }

  void setHealthy() {
    _mode = _ProxyMode.healthy;
    _slowHeight = null;
    _log('primary proxy mode=healthy');
  }

  void setSlowHeight(int height) {
    _mode = _ProxyMode.slowHeight;
    _slowHeight = height;
    _log('primary proxy mode=slowHeight height=$height');
  }

  void setDown() {
    _mode = _ProxyMode.down;
    _log('primary proxy mode=down');
  }

  void failNextSendTransactions(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    _sendTransactionFailuresRemaining = count;
    _log('primary proxy will fail next $count SendTransaction call(s)');
  }

  void _throwIfDown() {
    if (_mode == _ProxyMode.down) {
      throw grpc.GrpcError.unavailable('regtest primary proxy is down');
    }
  }

  service.BlockID _withModeHeight(service.BlockID block) {
    final slowHeight = _slowHeight;
    if (_mode != _ProxyMode.slowHeight || slowHeight == null) return block;
    if (block.height.toInt() <= slowHeight) return block;
    final copy = block.deepCopy();
    copy.height = Int64(slowHeight);
    return copy;
  }

  service.LightdInfo _withModeInfoHeight(service.LightdInfo info) {
    final slowHeight = _slowHeight;
    if (_mode != _ProxyMode.slowHeight || slowHeight == null) return info;
    final copy = info.deepCopy();
    final height = Int64(slowHeight);
    if (copy.blockHeight > height) copy.blockHeight = height;
    if (copy.estimatedHeight > height) copy.estimatedHeight = height;
    return copy;
  }

  @override
  Future<service.BlockID> getLatestBlock(
    grpc.ServiceCall call,
    service.ChainSpec request,
  ) async {
    _throwIfDown();
    return _withModeHeight(await _client.getLatestBlock(request));
  }

  @override
  Future<compact.CompactBlock> getBlock(
    grpc.ServiceCall call,
    service.BlockID request,
  ) {
    _throwIfDown();
    return _client.getBlock(request);
  }

  @override
  Future<compact.CompactBlock> getBlockNullifiers(
    grpc.ServiceCall call,
    service.BlockID request,
  ) {
    _throwIfDown();
    return _client.getBlockNullifiers(request);
  }

  @override
  Stream<compact.CompactBlock> getBlockRange(
    grpc.ServiceCall call,
    service.BlockRange request,
  ) {
    _throwIfDown();
    return _client.getBlockRange(request);
  }

  @override
  Stream<compact.CompactBlock> getBlockRangeNullifiers(
    grpc.ServiceCall call,
    service.BlockRange request,
  ) {
    _throwIfDown();
    return _client.getBlockRangeNullifiers(request);
  }

  @override
  Future<service.RawTransaction> getTransaction(
    grpc.ServiceCall call,
    service.TxFilter request,
  ) {
    _throwIfDown();
    return _client.getTransaction(request);
  }

  @override
  Future<service.SendResponse> sendTransaction(
    grpc.ServiceCall call,
    service.RawTransaction request,
  ) {
    _throwIfDown();
    if (_sendTransactionFailuresRemaining > 0) {
      _sendTransactionFailuresRemaining -= 1;
      _failedSendTransactionCount += 1;
      _log(
        'primary proxy forced SendTransaction failure '
        '(failed=$_failedSendTransactionCount)',
      );
      throw grpc.GrpcError.unavailable('forced SendTransaction failure');
    }
    return _client.sendTransaction(request);
  }

  @override
  Stream<service.RawTransaction> getTaddressTxids(
    grpc.ServiceCall call,
    service.TransparentAddressBlockFilter request,
  ) {
    _throwIfDown();
    return _client.getTaddressTxids(request);
  }

  @override
  Stream<service.RawTransaction> getTaddressTransactions(
    grpc.ServiceCall call,
    service.TransparentAddressBlockFilter request,
  ) {
    _throwIfDown();
    return _client.getTaddressTransactions(request);
  }

  @override
  Future<service.Balance> getTaddressBalance(
    grpc.ServiceCall call,
    service.AddressList request,
  ) {
    _throwIfDown();
    return _client.getTaddressBalance(request);
  }

  @override
  Future<service.Balance> getTaddressBalanceStream(
    grpc.ServiceCall call,
    Stream<service.Address> request,
  ) {
    _throwIfDown();
    return _client.getTaddressBalanceStream(request);
  }

  @override
  Stream<compact.CompactTx> getMempoolTx(
    grpc.ServiceCall call,
    service.GetMempoolTxRequest request,
  ) {
    _throwIfDown();
    return _client.getMempoolTx(request);
  }

  @override
  Stream<service.RawTransaction> getMempoolStream(
    grpc.ServiceCall call,
    service.Empty request,
  ) {
    _throwIfDown();
    return _client.getMempoolStream(request);
  }

  @override
  Future<service.TreeState> getTreeState(
    grpc.ServiceCall call,
    service.BlockID request,
  ) {
    _throwIfDown();
    return _client.getTreeState(request);
  }

  @override
  Future<service.TreeState> getLatestTreeState(
    grpc.ServiceCall call,
    service.Empty request,
  ) {
    _throwIfDown();
    return _client.getLatestTreeState(request);
  }

  @override
  Stream<service.SubtreeRoot> getSubtreeRoots(
    grpc.ServiceCall call,
    service.GetSubtreeRootsArg request,
  ) {
    _throwIfDown();
    return _client.getSubtreeRoots(request);
  }

  @override
  Future<service.GetAddressUtxosReplyList> getAddressUtxos(
    grpc.ServiceCall call,
    service.GetAddressUtxosArg request,
  ) {
    _throwIfDown();
    return _client.getAddressUtxos(request);
  }

  @override
  Stream<service.GetAddressUtxosReply> getAddressUtxosStream(
    grpc.ServiceCall call,
    service.GetAddressUtxosArg request,
  ) {
    _throwIfDown();
    return _client.getAddressUtxosStream(request);
  }

  @override
  Future<service.LightdInfo> getLightdInfo(
    grpc.ServiceCall call,
    service.Empty request,
  ) async {
    _throwIfDown();
    return _withModeInfoHeight(await _client.getLightdInfo(request));
  }

  @override
  Future<service.PingResponse> ping(
    grpc.ServiceCall call,
    service.Duration request,
  ) {
    _throwIfDown();
    return _client.ping(request);
  }
}
