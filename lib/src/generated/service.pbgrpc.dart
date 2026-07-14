// This is a generated file - do not edit.
//
// Generated from service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'compact_formats.pb.dart' as $1;
import 'service.pb.dart' as $0;

export 'service.pb.dart';

@$pb.GrpcServiceName('cash.z.wallet.sdk.rpc.CompactTxStreamer')
class CompactTxStreamerClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  CompactTxStreamerClient(super.channel, {super.options, super.interceptors});

  /// Return the BlockID of the block at the tip of the best chain
  $grpc.ResponseFuture<$0.BlockID> getLatestBlock(
    $0.ChainSpec request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getLatestBlock, request, options: options);
  }

  /// Return the compact block corresponding to the given block identifier.
  ///
  /// The returned `CompactBlock` includes transaction data for all value
  /// pools, including transparent inputs (`vin`) and outputs (`vout`). This
  /// differs from `GetBlockRange`, which supports filtering by pool type and
  /// defaults to returning only shielded (Sapling, Orchard, and Ironwood) data. Clients
  /// that require only data for specific pools should use `GetBlockRange`
  /// with the appropriate `poolTypes` set.
  ///
  /// Note: the single null-outpoint input for coinbase transactions is
  /// omitted from the `vin` field of the corresponding `CompactTx`. See the
  /// documentation of the `CompactTx` message for details.
  $grpc.ResponseFuture<$1.CompactBlock> getBlock(
    $0.BlockID request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getBlock, request, options: options);
  }

  /// Return a compact block containing only nullifier information for the
  /// shielded pools (Sapling spend nullifiers, Orchard action nullifiers, and
  /// Ironwood action nullifiers). Transparent transaction data, Sapling
  /// outputs, full Orchard/Ironwood action data, and commitment tree sizes are
  /// not included.
  ///
  /// Note: this method is deprecated; use `GetBlockRange` with the
  /// appropriate `poolTypes` instead.
  @$core.Deprecated('This method is deprecated')
  $grpc.ResponseFuture<$1.CompactBlock> getBlockNullifiers(
    $0.BlockID request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getBlockNullifiers, request, options: options);
  }

  /// Return a list of consecutive compact blocks in the specified range,
  /// which is inclusive of `range.end`.
  ///
  /// If range.start <= range.end, blocks are returned increasing height order;
  /// otherwise blocks are returned in decreasing height order.
  $grpc.ResponseStream<$1.CompactBlock> getBlockRange(
    $0.BlockRange request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getBlockRange, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Return a stream of compact blocks for the specified range, where each
  /// block contains only nullifier information for the shielded pools
  /// (Sapling spend nullifiers, Orchard action nullifiers, and Ironwood action
  /// nullifiers). Transparent transaction data, Sapling outputs, full
  /// Orchard/Ironwood action data, and commitment tree sizes are not included.
  /// Implementations MUST ignore any
  /// `PoolType::TRANSPARENT` member of the `poolTypes` field of the request.
  ///
  /// Note: this method is deprecated; use `GetBlockRange` with the
  /// appropriate `poolTypes` instead.
  @$core.Deprecated('This method is deprecated')
  $grpc.ResponseStream<$1.CompactBlock> getBlockRangeNullifiers(
    $0.BlockRange request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getBlockRangeNullifiers, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Return the requested full (not compact) transaction (as from zcashd)
  $grpc.ResponseFuture<$0.RawTransaction> getTransaction(
    $0.TxFilter request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTransaction, request, options: options);
  }

  /// Submit the given transaction to the Zcash network
  $grpc.ResponseFuture<$0.SendResponse> sendTransaction(
    $0.RawTransaction request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$sendTransaction, request, options: options);
  }

  /// Return RawTransactions that match the given transparent address filter.
  ///
  /// Note: This function is misnamed, it returns complete `RawTransaction` values, not TxIds.
  /// NOTE: this method is deprecated, please use GetTaddressTransactions instead.
  $grpc.ResponseStream<$0.RawTransaction> getTaddressTxids(
    $0.TransparentAddressBlockFilter request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getTaddressTxids, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Return the transactions corresponding to the given t-address within the given block range.
  /// Mempool transactions are not included in the results.
  $grpc.ResponseStream<$0.RawTransaction> getTaddressTransactions(
    $0.TransparentAddressBlockFilter request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getTaddressTransactions, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.Balance> getTaddressBalance(
    $0.AddressList request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTaddressBalance, request, options: options);
  }

  $grpc.ResponseFuture<$0.Balance> getTaddressBalanceStream(
    $async.Stream<$0.Address> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$getTaddressBalanceStream, request,
            options: options)
        .single;
  }

  /// Returns a stream of the compact transaction representation for transactions
  /// currently in the mempool. The results of this operation may be a few
  /// seconds out of date. If the `exclude_txid_suffixes` list is empty,
  /// return all transactions; otherwise return all *except* those in the
  /// `exclude_txid_suffixes` list (if any); this allows the client to avoid
  /// receiving transactions that it already has (from an earlier call to this
  /// RPC). The transaction IDs in the `exclude_txid_suffixes` list can be
  /// shortened to any number of bytes to make the request more
  /// bandwidth-efficient; if two or more transactions in the mempool match a
  /// txid suffix, none of the matching transactions are excluded. Txid
  /// suffixes in the exclude list that don't match any transactions in the
  /// mempool are ignored.
  $grpc.ResponseStream<$1.CompactTx> getMempoolTx(
    $0.GetMempoolTxRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getMempoolTx, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Return a stream of current Mempool transactions. This will keep the output stream open while
  /// there are mempool transactions. It will close the returned stream when a new block is mined.
  $grpc.ResponseStream<$0.RawTransaction> getMempoolStream(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getMempoolStream, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// GetTreeState returns the note commitment tree state corresponding to the given block.
  /// See section 3.7 of the Zcash protocol specification. It returns several other useful
  /// values also (even though they can be obtained using GetBlock).
  /// The block can be specified by either height or hash.
  $grpc.ResponseFuture<$0.TreeState> getTreeState(
    $0.BlockID request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTreeState, request, options: options);
  }

  $grpc.ResponseFuture<$0.TreeState> getLatestTreeState(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getLatestTreeState, request, options: options);
  }

  /// Returns a stream of information about roots of subtrees of the note commitment tree
  /// for the specified shielded protocol (Sapling, Orchard, or Ironwood).
  $grpc.ResponseStream<$0.SubtreeRoot> getSubtreeRoots(
    $0.GetSubtreeRootsArg request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getSubtreeRoots, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.GetAddressUtxosReplyList> getAddressUtxos(
    $0.GetAddressUtxosArg request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getAddressUtxos, request, options: options);
  }

  $grpc.ResponseStream<$0.GetAddressUtxosReply> getAddressUtxosStream(
    $0.GetAddressUtxosArg request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$getAddressUtxosStream, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Return information about this lightwalletd instance and the blockchain
  $grpc.ResponseFuture<$0.LightdInfo> getLightdInfo(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getLightdInfo, request, options: options);
  }

  /// Testing-only, requires lightwalletd --ping-very-insecure (do not enable in production)
  $grpc.ResponseFuture<$0.PingResponse> ping(
    $0.Duration request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$ping, request, options: options);
  }

  // method descriptors

  static final _$getLatestBlock = $grpc.ClientMethod<$0.ChainSpec, $0.BlockID>(
      '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock',
      ($0.ChainSpec value) => value.writeToBuffer(),
      $0.BlockID.fromBuffer);
  static final _$getBlock = $grpc.ClientMethod<$0.BlockID, $1.CompactBlock>(
      '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlock',
      ($0.BlockID value) => value.writeToBuffer(),
      $1.CompactBlock.fromBuffer);
  static final _$getBlockNullifiers =
      $grpc.ClientMethod<$0.BlockID, $1.CompactBlock>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockNullifiers',
          ($0.BlockID value) => value.writeToBuffer(),
          $1.CompactBlock.fromBuffer);
  static final _$getBlockRange =
      $grpc.ClientMethod<$0.BlockRange, $1.CompactBlock>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockRange',
          ($0.BlockRange value) => value.writeToBuffer(),
          $1.CompactBlock.fromBuffer);
  static final _$getBlockRangeNullifiers =
      $grpc.ClientMethod<$0.BlockRange, $1.CompactBlock>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockRangeNullifiers',
          ($0.BlockRange value) => value.writeToBuffer(),
          $1.CompactBlock.fromBuffer);
  static final _$getTransaction =
      $grpc.ClientMethod<$0.TxFilter, $0.RawTransaction>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTransaction',
          ($0.TxFilter value) => value.writeToBuffer(),
          $0.RawTransaction.fromBuffer);
  static final _$sendTransaction =
      $grpc.ClientMethod<$0.RawTransaction, $0.SendResponse>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/SendTransaction',
          ($0.RawTransaction value) => value.writeToBuffer(),
          $0.SendResponse.fromBuffer);
  static final _$getTaddressTxids =
      $grpc.ClientMethod<$0.TransparentAddressBlockFilter, $0.RawTransaction>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressTxids',
          ($0.TransparentAddressBlockFilter value) => value.writeToBuffer(),
          $0.RawTransaction.fromBuffer);
  static final _$getTaddressTransactions =
      $grpc.ClientMethod<$0.TransparentAddressBlockFilter, $0.RawTransaction>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressTransactions',
          ($0.TransparentAddressBlockFilter value) => value.writeToBuffer(),
          $0.RawTransaction.fromBuffer);
  static final _$getTaddressBalance =
      $grpc.ClientMethod<$0.AddressList, $0.Balance>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressBalance',
          ($0.AddressList value) => value.writeToBuffer(),
          $0.Balance.fromBuffer);
  static final _$getTaddressBalanceStream =
      $grpc.ClientMethod<$0.Address, $0.Balance>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressBalanceStream',
          ($0.Address value) => value.writeToBuffer(),
          $0.Balance.fromBuffer);
  static final _$getMempoolTx =
      $grpc.ClientMethod<$0.GetMempoolTxRequest, $1.CompactTx>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetMempoolTx',
          ($0.GetMempoolTxRequest value) => value.writeToBuffer(),
          $1.CompactTx.fromBuffer);
  static final _$getMempoolStream =
      $grpc.ClientMethod<$0.Empty, $0.RawTransaction>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetMempoolStream',
          ($0.Empty value) => value.writeToBuffer(),
          $0.RawTransaction.fromBuffer);
  static final _$getTreeState = $grpc.ClientMethod<$0.BlockID, $0.TreeState>(
      '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTreeState',
      ($0.BlockID value) => value.writeToBuffer(),
      $0.TreeState.fromBuffer);
  static final _$getLatestTreeState =
      $grpc.ClientMethod<$0.Empty, $0.TreeState>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestTreeState',
          ($0.Empty value) => value.writeToBuffer(),
          $0.TreeState.fromBuffer);
  static final _$getSubtreeRoots =
      $grpc.ClientMethod<$0.GetSubtreeRootsArg, $0.SubtreeRoot>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetSubtreeRoots',
          ($0.GetSubtreeRootsArg value) => value.writeToBuffer(),
          $0.SubtreeRoot.fromBuffer);
  static final _$getAddressUtxos =
      $grpc.ClientMethod<$0.GetAddressUtxosArg, $0.GetAddressUtxosReplyList>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetAddressUtxos',
          ($0.GetAddressUtxosArg value) => value.writeToBuffer(),
          $0.GetAddressUtxosReplyList.fromBuffer);
  static final _$getAddressUtxosStream =
      $grpc.ClientMethod<$0.GetAddressUtxosArg, $0.GetAddressUtxosReply>(
          '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetAddressUtxosStream',
          ($0.GetAddressUtxosArg value) => value.writeToBuffer(),
          $0.GetAddressUtxosReply.fromBuffer);
  static final _$getLightdInfo = $grpc.ClientMethod<$0.Empty, $0.LightdInfo>(
      '/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo',
      ($0.Empty value) => value.writeToBuffer(),
      $0.LightdInfo.fromBuffer);
  static final _$ping = $grpc.ClientMethod<$0.Duration, $0.PingResponse>(
      '/cash.z.wallet.sdk.rpc.CompactTxStreamer/Ping',
      ($0.Duration value) => value.writeToBuffer(),
      $0.PingResponse.fromBuffer);
}

@$pb.GrpcServiceName('cash.z.wallet.sdk.rpc.CompactTxStreamer')
abstract class CompactTxStreamerServiceBase extends $grpc.Service {
  $core.String get $name => 'cash.z.wallet.sdk.rpc.CompactTxStreamer';

  CompactTxStreamerServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ChainSpec, $0.BlockID>(
        'GetLatestBlock',
        getLatestBlock_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ChainSpec.fromBuffer(value),
        ($0.BlockID value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.BlockID, $1.CompactBlock>(
        'GetBlock',
        getBlock_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.BlockID.fromBuffer(value),
        ($1.CompactBlock value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.BlockID, $1.CompactBlock>(
        'GetBlockNullifiers',
        getBlockNullifiers_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.BlockID.fromBuffer(value),
        ($1.CompactBlock value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.BlockRange, $1.CompactBlock>(
        'GetBlockRange',
        getBlockRange_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.BlockRange.fromBuffer(value),
        ($1.CompactBlock value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.BlockRange, $1.CompactBlock>(
        'GetBlockRangeNullifiers',
        getBlockRangeNullifiers_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.BlockRange.fromBuffer(value),
        ($1.CompactBlock value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TxFilter, $0.RawTransaction>(
        'GetTransaction',
        getTransaction_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.TxFilter.fromBuffer(value),
        ($0.RawTransaction value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RawTransaction, $0.SendResponse>(
        'SendTransaction',
        sendTransaction_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.RawTransaction.fromBuffer(value),
        ($0.SendResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TransparentAddressBlockFilter,
            $0.RawTransaction>(
        'GetTaddressTxids',
        getTaddressTxids_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.TransparentAddressBlockFilter.fromBuffer(value),
        ($0.RawTransaction value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TransparentAddressBlockFilter,
            $0.RawTransaction>(
        'GetTaddressTransactions',
        getTaddressTransactions_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.TransparentAddressBlockFilter.fromBuffer(value),
        ($0.RawTransaction value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AddressList, $0.Balance>(
        'GetTaddressBalance',
        getTaddressBalance_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.AddressList.fromBuffer(value),
        ($0.Balance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Address, $0.Balance>(
        'GetTaddressBalanceStream',
        getTaddressBalanceStream,
        true,
        false,
        ($core.List<$core.int> value) => $0.Address.fromBuffer(value),
        ($0.Balance value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMempoolTxRequest, $1.CompactTx>(
        'GetMempoolTx',
        getMempoolTx_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.GetMempoolTxRequest.fromBuffer(value),
        ($1.CompactTx value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.RawTransaction>(
        'GetMempoolStream',
        getMempoolStream_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.RawTransaction value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.BlockID, $0.TreeState>(
        'GetTreeState',
        getTreeState_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.BlockID.fromBuffer(value),
        ($0.TreeState value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.TreeState>(
        'GetLatestTreeState',
        getLatestTreeState_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.TreeState value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetSubtreeRootsArg, $0.SubtreeRoot>(
        'GetSubtreeRoots',
        getSubtreeRoots_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.GetSubtreeRootsArg.fromBuffer(value),
        ($0.SubtreeRoot value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetAddressUtxosArg, $0.GetAddressUtxosReplyList>(
            'GetAddressUtxos',
            getAddressUtxos_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetAddressUtxosArg.fromBuffer(value),
            ($0.GetAddressUtxosReplyList value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetAddressUtxosArg, $0.GetAddressUtxosReply>(
            'GetAddressUtxosStream',
            getAddressUtxosStream_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.GetAddressUtxosArg.fromBuffer(value),
            ($0.GetAddressUtxosReply value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.LightdInfo>(
        'GetLightdInfo',
        getLightdInfo_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.LightdInfo value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Duration, $0.PingResponse>(
        'Ping',
        ping_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Duration.fromBuffer(value),
        ($0.PingResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.BlockID> getLatestBlock_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ChainSpec> $request) async {
    return getLatestBlock($call, await $request);
  }

  $async.Future<$0.BlockID> getLatestBlock(
      $grpc.ServiceCall call, $0.ChainSpec request);

  $async.Future<$1.CompactBlock> getBlock_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.BlockID> $request) async {
    return getBlock($call, await $request);
  }

  $async.Future<$1.CompactBlock> getBlock(
      $grpc.ServiceCall call, $0.BlockID request);

  $async.Future<$1.CompactBlock> getBlockNullifiers_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.BlockID> $request) async {
    return getBlockNullifiers($call, await $request);
  }

  $async.Future<$1.CompactBlock> getBlockNullifiers(
      $grpc.ServiceCall call, $0.BlockID request);

  $async.Stream<$1.CompactBlock> getBlockRange_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.BlockRange> $request) async* {
    yield* getBlockRange($call, await $request);
  }

  $async.Stream<$1.CompactBlock> getBlockRange(
      $grpc.ServiceCall call, $0.BlockRange request);

  $async.Stream<$1.CompactBlock> getBlockRangeNullifiers_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.BlockRange> $request) async* {
    yield* getBlockRangeNullifiers($call, await $request);
  }

  $async.Stream<$1.CompactBlock> getBlockRangeNullifiers(
      $grpc.ServiceCall call, $0.BlockRange request);

  $async.Future<$0.RawTransaction> getTransaction_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.TxFilter> $request) async {
    return getTransaction($call, await $request);
  }

  $async.Future<$0.RawTransaction> getTransaction(
      $grpc.ServiceCall call, $0.TxFilter request);

  $async.Future<$0.SendResponse> sendTransaction_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RawTransaction> $request) async {
    return sendTransaction($call, await $request);
  }

  $async.Future<$0.SendResponse> sendTransaction(
      $grpc.ServiceCall call, $0.RawTransaction request);

  $async.Stream<$0.RawTransaction> getTaddressTxids_Pre($grpc.ServiceCall $call,
      $async.Future<$0.TransparentAddressBlockFilter> $request) async* {
    yield* getTaddressTxids($call, await $request);
  }

  $async.Stream<$0.RawTransaction> getTaddressTxids(
      $grpc.ServiceCall call, $0.TransparentAddressBlockFilter request);

  $async.Stream<$0.RawTransaction> getTaddressTransactions_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.TransparentAddressBlockFilter> $request) async* {
    yield* getTaddressTransactions($call, await $request);
  }

  $async.Stream<$0.RawTransaction> getTaddressTransactions(
      $grpc.ServiceCall call, $0.TransparentAddressBlockFilter request);

  $async.Future<$0.Balance> getTaddressBalance_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.AddressList> $request) async {
    return getTaddressBalance($call, await $request);
  }

  $async.Future<$0.Balance> getTaddressBalance(
      $grpc.ServiceCall call, $0.AddressList request);

  $async.Future<$0.Balance> getTaddressBalanceStream(
      $grpc.ServiceCall call, $async.Stream<$0.Address> request);

  $async.Stream<$1.CompactTx> getMempoolTx_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetMempoolTxRequest> $request) async* {
    yield* getMempoolTx($call, await $request);
  }

  $async.Stream<$1.CompactTx> getMempoolTx(
      $grpc.ServiceCall call, $0.GetMempoolTxRequest request);

  $async.Stream<$0.RawTransaction> getMempoolStream_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async* {
    yield* getMempoolStream($call, await $request);
  }

  $async.Stream<$0.RawTransaction> getMempoolStream(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.TreeState> getTreeState_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.BlockID> $request) async {
    return getTreeState($call, await $request);
  }

  $async.Future<$0.TreeState> getTreeState(
      $grpc.ServiceCall call, $0.BlockID request);

  $async.Future<$0.TreeState> getLatestTreeState_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getLatestTreeState($call, await $request);
  }

  $async.Future<$0.TreeState> getLatestTreeState(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Stream<$0.SubtreeRoot> getSubtreeRoots_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetSubtreeRootsArg> $request) async* {
    yield* getSubtreeRoots($call, await $request);
  }

  $async.Stream<$0.SubtreeRoot> getSubtreeRoots(
      $grpc.ServiceCall call, $0.GetSubtreeRootsArg request);

  $async.Future<$0.GetAddressUtxosReplyList> getAddressUtxos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetAddressUtxosArg> $request) async {
    return getAddressUtxos($call, await $request);
  }

  $async.Future<$0.GetAddressUtxosReplyList> getAddressUtxos(
      $grpc.ServiceCall call, $0.GetAddressUtxosArg request);

  $async.Stream<$0.GetAddressUtxosReply> getAddressUtxosStream_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetAddressUtxosArg> $request) async* {
    yield* getAddressUtxosStream($call, await $request);
  }

  $async.Stream<$0.GetAddressUtxosReply> getAddressUtxosStream(
      $grpc.ServiceCall call, $0.GetAddressUtxosArg request);

  $async.Future<$0.LightdInfo> getLightdInfo_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getLightdInfo($call, await $request);
  }

  $async.Future<$0.LightdInfo> getLightdInfo(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.PingResponse> ping_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Duration> $request) async {
    return ping($call, await $request);
  }

  $async.Future<$0.PingResponse> ping(
      $grpc.ServiceCall call, $0.Duration request);
}
