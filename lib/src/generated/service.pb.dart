// This is a generated file - do not edit.
//
// Generated from service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'service.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'service.pbenum.dart';

/// A BlockID message contains identifiers to select a block: a height or a
/// hash. Support for specification by hash is not mandatory. (If `hash` is
/// non-empty, the rpc may return an error.) This field is present to support
/// a possible future upgrade.
class BlockID extends $pb.GeneratedMessage {
  factory BlockID({
    $fixnum.Int64? height,
    $core.List<$core.int>? hash,
  }) {
    final result = create();
    if (height != null) result.height = height;
    if (hash != null) result.hash = hash;
    return result;
  }

  BlockID._();

  factory BlockID.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BlockID.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BlockID',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'height', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'hash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BlockID clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BlockID copyWith(void Function(BlockID) updates) =>
      super.copyWith((message) => updates(message as BlockID)) as BlockID;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BlockID create() => BlockID._();
  @$core.override
  BlockID createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BlockID getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BlockID>(create);
  static BlockID? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get height => $_getI64(0);
  @$pb.TagNumber(1)
  set height($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHeight() => $_has(0);
  @$pb.TagNumber(1)
  void clearHeight() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get hash => $_getN(1);
  @$pb.TagNumber(2)
  set hash($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHash() => $_has(1);
  @$pb.TagNumber(2)
  void clearHash() => $_clearField(2);
}

/// BlockRange specifies a series of blocks from start to end inclusive.
/// Both BlockIDs must be heights; specification by hash is not yet supported.
///
/// If no pool types are specified, the server should default to the legacy
/// behavior of returning only data relevant to the shielded (Sapling, Orchard,
/// and Ironwood) pools; otherwise, the server should prune `CompactBlock`s returned
/// to include only data relevant to the requested pool types. Clients MUST
/// verify that the version of the server they are connected to are capable
/// of returning pruned and/or transparent data before setting `poolTypes`
/// to a non-empty value.
class BlockRange extends $pb.GeneratedMessage {
  factory BlockRange({
    BlockID? start,
    BlockID? end,
    $core.Iterable<PoolType>? poolTypes,
  }) {
    final result = create();
    if (start != null) result.start = start;
    if (end != null) result.end = end;
    if (poolTypes != null) result.poolTypes.addAll(poolTypes);
    return result;
  }

  BlockRange._();

  factory BlockRange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BlockRange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BlockRange',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aOM<BlockID>(1, _omitFieldNames ? '' : 'start',
        subBuilder: BlockID.create)
    ..aOM<BlockID>(2, _omitFieldNames ? '' : 'end', subBuilder: BlockID.create)
    ..pc<PoolType>(3, _omitFieldNames ? '' : 'poolTypes', $pb.PbFieldType.KE,
        protoName: 'poolTypes',
        valueOf: PoolType.valueOf,
        enumValues: PoolType.values,
        defaultEnumValue: PoolType.POOL_TYPE_INVALID)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BlockRange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BlockRange copyWith(void Function(BlockRange) updates) =>
      super.copyWith((message) => updates(message as BlockRange)) as BlockRange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BlockRange create() => BlockRange._();
  @$core.override
  BlockRange createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BlockRange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BlockRange>(create);
  static BlockRange? _defaultInstance;

  @$pb.TagNumber(1)
  BlockID get start => $_getN(0);
  @$pb.TagNumber(1)
  set start(BlockID value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearStart() => $_clearField(1);
  @$pb.TagNumber(1)
  BlockID ensureStart() => $_ensure(0);

  @$pb.TagNumber(2)
  BlockID get end => $_getN(1);
  @$pb.TagNumber(2)
  set end(BlockID value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEnd() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnd() => $_clearField(2);
  @$pb.TagNumber(2)
  BlockID ensureEnd() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<PoolType> get poolTypes => $_getList(2);
}

/// A TxFilter contains the information needed to identify a particular
/// transaction: either a block and an index, or a direct transaction hash.
/// Currently, only specification by hash is supported.
class TxFilter extends $pb.GeneratedMessage {
  factory TxFilter({
    BlockID? block,
    $fixnum.Int64? index,
    $core.List<$core.int>? hash,
  }) {
    final result = create();
    if (block != null) result.block = block;
    if (index != null) result.index = index;
    if (hash != null) result.hash = hash;
    return result;
  }

  TxFilter._();

  factory TxFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TxFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TxFilter',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aOM<BlockID>(1, _omitFieldNames ? '' : 'block',
        subBuilder: BlockID.create)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'index', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'hash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TxFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TxFilter copyWith(void Function(TxFilter) updates) =>
      super.copyWith((message) => updates(message as TxFilter)) as TxFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TxFilter create() => TxFilter._();
  @$core.override
  TxFilter createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TxFilter getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TxFilter>(create);
  static TxFilter? _defaultInstance;

  @$pb.TagNumber(1)
  BlockID get block => $_getN(0);
  @$pb.TagNumber(1)
  set block(BlockID value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBlock() => $_has(0);
  @$pb.TagNumber(1)
  void clearBlock() => $_clearField(1);
  @$pb.TagNumber(1)
  BlockID ensureBlock() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get index => $_getI64(1);
  @$pb.TagNumber(2)
  set index($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndex() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get hash => $_getN(2);
  @$pb.TagNumber(3)
  set hash($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearHash() => $_clearField(3);
}

/// RawTransaction contains the complete transaction data. It also optionally includes
/// the block height in which the transaction was included, or, when returned
/// by GetMempoolStream(), the latest block height.
///
/// FIXME: the documentation here about mempool status contradicts the documentation
/// for the `height` field. See https://github.com/zcash/librustzcash/issues/1484
class RawTransaction extends $pb.GeneratedMessage {
  factory RawTransaction({
    $core.List<$core.int>? data,
    $fixnum.Int64? height,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (height != null) result.height = height;
    return result;
  }

  RawTransaction._();

  factory RawTransaction.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RawTransaction.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RawTransaction',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'height', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RawTransaction clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RawTransaction copyWith(void Function(RawTransaction) updates) =>
      super.copyWith((message) => updates(message as RawTransaction))
          as RawTransaction;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RawTransaction create() => RawTransaction._();
  @$core.override
  RawTransaction createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RawTransaction getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RawTransaction>(create);
  static RawTransaction? _defaultInstance;

  /// The serialized representation of the Zcash transaction.
  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  /// The height at which the transaction is mined, or a sentinel value.
  ///
  /// Due to an error in the original protobuf definition, it is necessary to
  /// reinterpret the result of the `getrawtransaction` RPC call. Zcashd will
  /// return the int64 value `-1` for the height of transactions that appear
  /// in the block index, but which are not mined in the main chain. Here, the
  /// height field of `RawTransaction` was erroneously created as a `uint64`,
  /// and as such we must map the response from the zcashd RPC API to be
  /// representable within this space. Additionally, the `height` field will
  /// be absent for transactions in the mempool, resulting in the default
  /// value of `0` being set. Therefore, the meanings of the `height` field of
  /// the `RawTransaction` type are as follows:
  ///
  /// * height 0: the transaction is in the mempool
  /// * height 0xffffffffffffffff: the transaction has been mined on a fork that
  ///   is not currently the main chain
  /// * any other height: the transaction has been mined in the main chain at the
  ///   given height
  @$pb.TagNumber(2)
  $fixnum.Int64 get height => $_getI64(1);
  @$pb.TagNumber(2)
  set height($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeight() => $_clearField(2);
}

/// A SendResponse encodes an error code and a string. It is currently used
/// only by SendTransaction(). If error code is zero, the operation was
/// successful; if non-zero, it and the message specify the failure.
class SendResponse extends $pb.GeneratedMessage {
  factory SendResponse({
    $core.int? errorCode,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (errorCode != null) result.errorCode = errorCode;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  SendResponse._();

  factory SendResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SendResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'errorCode', protoName: 'errorCode')
    ..aOS(2, _omitFieldNames ? '' : 'errorMessage', protoName: 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendResponse copyWith(void Function(SendResponse) updates) =>
      super.copyWith((message) => updates(message as SendResponse))
          as SendResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendResponse create() => SendResponse._();
  @$core.override
  SendResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SendResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendResponse>(create);
  static SendResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get errorCode => $_getIZ(0);
  @$pb.TagNumber(1)
  set errorCode($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasErrorCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearErrorCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get errorMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set errorMessage($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasErrorMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearErrorMessage() => $_clearField(2);
}

/// Chainspec is a placeholder to allow specification of a particular chain fork.
class ChainSpec extends $pb.GeneratedMessage {
  factory ChainSpec() => create();

  ChainSpec._();

  factory ChainSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChainSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChainSpec',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChainSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChainSpec copyWith(void Function(ChainSpec) updates) =>
      super.copyWith((message) => updates(message as ChainSpec)) as ChainSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChainSpec create() => ChainSpec._();
  @$core.override
  ChainSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChainSpec getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChainSpec>(create);
  static ChainSpec? _defaultInstance;
}

/// Empty is for gRPCs that take no arguments, currently only GetLightdInfo.
class Empty extends $pb.GeneratedMessage {
  factory Empty() => create();

  Empty._();

  factory Empty.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Empty.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Empty',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty copyWith(void Function(Empty) updates) =>
      super.copyWith((message) => updates(message as Empty)) as Empty;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Empty create() => Empty._();
  @$core.override
  Empty createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Empty getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Empty>(create);
  static Empty? _defaultInstance;
}

/// LightdInfo returns various information about this lightwalletd instance
/// and the state of the blockchain.
class LightdInfo extends $pb.GeneratedMessage {
  factory LightdInfo({
    $core.String? version,
    $core.String? vendor,
    $core.bool? taddrSupport,
    $core.String? chainName,
    $fixnum.Int64? saplingActivationHeight,
    $core.String? consensusBranchId,
    $fixnum.Int64? blockHeight,
    $core.String? gitCommit,
    $core.String? branch,
    $core.String? buildDate,
    $core.String? buildUser,
    $fixnum.Int64? estimatedHeight,
    $core.String? zcashdBuild,
    $core.String? zcashdSubversion,
    $core.String? donationAddress,
    $core.String? upgradeName,
    $fixnum.Int64? upgradeHeight,
    $core.String? lightwalletProtocolVersion,
  }) {
    final result = create();
    if (version != null) result.version = version;
    if (vendor != null) result.vendor = vendor;
    if (taddrSupport != null) result.taddrSupport = taddrSupport;
    if (chainName != null) result.chainName = chainName;
    if (saplingActivationHeight != null)
      result.saplingActivationHeight = saplingActivationHeight;
    if (consensusBranchId != null) result.consensusBranchId = consensusBranchId;
    if (blockHeight != null) result.blockHeight = blockHeight;
    if (gitCommit != null) result.gitCommit = gitCommit;
    if (branch != null) result.branch = branch;
    if (buildDate != null) result.buildDate = buildDate;
    if (buildUser != null) result.buildUser = buildUser;
    if (estimatedHeight != null) result.estimatedHeight = estimatedHeight;
    if (zcashdBuild != null) result.zcashdBuild = zcashdBuild;
    if (zcashdSubversion != null) result.zcashdSubversion = zcashdSubversion;
    if (donationAddress != null) result.donationAddress = donationAddress;
    if (upgradeName != null) result.upgradeName = upgradeName;
    if (upgradeHeight != null) result.upgradeHeight = upgradeHeight;
    if (lightwalletProtocolVersion != null)
      result.lightwalletProtocolVersion = lightwalletProtocolVersion;
    return result;
  }

  LightdInfo._();

  factory LightdInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LightdInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LightdInfo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'version')
    ..aOS(2, _omitFieldNames ? '' : 'vendor')
    ..aOB(3, _omitFieldNames ? '' : 'taddrSupport', protoName: 'taddrSupport')
    ..aOS(4, _omitFieldNames ? '' : 'chainName', protoName: 'chainName')
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'saplingActivationHeight',
        $pb.PbFieldType.OU6,
        protoName: 'saplingActivationHeight',
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(6, _omitFieldNames ? '' : 'consensusBranchId',
        protoName: 'consensusBranchId')
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'blockHeight', $pb.PbFieldType.OU6,
        protoName: 'blockHeight', defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(8, _omitFieldNames ? '' : 'gitCommit', protoName: 'gitCommit')
    ..aOS(9, _omitFieldNames ? '' : 'branch')
    ..aOS(10, _omitFieldNames ? '' : 'buildDate', protoName: 'buildDate')
    ..aOS(11, _omitFieldNames ? '' : 'buildUser', protoName: 'buildUser')
    ..a<$fixnum.Int64>(
        12, _omitFieldNames ? '' : 'estimatedHeight', $pb.PbFieldType.OU6,
        protoName: 'estimatedHeight', defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(13, _omitFieldNames ? '' : 'zcashdBuild', protoName: 'zcashdBuild')
    ..aOS(14, _omitFieldNames ? '' : 'zcashdSubversion',
        protoName: 'zcashdSubversion')
    ..aOS(15, _omitFieldNames ? '' : 'donationAddress',
        protoName: 'donationAddress')
    ..aOS(16, _omitFieldNames ? '' : 'upgradeName', protoName: 'upgradeName')
    ..a<$fixnum.Int64>(
        17, _omitFieldNames ? '' : 'upgradeHeight', $pb.PbFieldType.OU6,
        protoName: 'upgradeHeight', defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(18, _omitFieldNames ? '' : 'lightwalletProtocolVersion',
        protoName: 'lightwalletProtocolVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LightdInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LightdInfo copyWith(void Function(LightdInfo) updates) =>
      super.copyWith((message) => updates(message as LightdInfo)) as LightdInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LightdInfo create() => LightdInfo._();
  @$core.override
  LightdInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LightdInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LightdInfo>(create);
  static LightdInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get version => $_getSZ(0);
  @$pb.TagNumber(1)
  set version($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get vendor => $_getSZ(1);
  @$pb.TagNumber(2)
  set vendor($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVendor() => $_has(1);
  @$pb.TagNumber(2)
  void clearVendor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get taddrSupport => $_getBF(2);
  @$pb.TagNumber(3)
  set taddrSupport($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTaddrSupport() => $_has(2);
  @$pb.TagNumber(3)
  void clearTaddrSupport() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get chainName => $_getSZ(3);
  @$pb.TagNumber(4)
  set chainName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasChainName() => $_has(3);
  @$pb.TagNumber(4)
  void clearChainName() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get saplingActivationHeight => $_getI64(4);
  @$pb.TagNumber(5)
  set saplingActivationHeight($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSaplingActivationHeight() => $_has(4);
  @$pb.TagNumber(5)
  void clearSaplingActivationHeight() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get consensusBranchId => $_getSZ(5);
  @$pb.TagNumber(6)
  set consensusBranchId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasConsensusBranchId() => $_has(5);
  @$pb.TagNumber(6)
  void clearConsensusBranchId() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get blockHeight => $_getI64(6);
  @$pb.TagNumber(7)
  set blockHeight($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasBlockHeight() => $_has(6);
  @$pb.TagNumber(7)
  void clearBlockHeight() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get gitCommit => $_getSZ(7);
  @$pb.TagNumber(8)
  set gitCommit($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasGitCommit() => $_has(7);
  @$pb.TagNumber(8)
  void clearGitCommit() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get branch => $_getSZ(8);
  @$pb.TagNumber(9)
  set branch($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBranch() => $_has(8);
  @$pb.TagNumber(9)
  void clearBranch() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get buildDate => $_getSZ(9);
  @$pb.TagNumber(10)
  set buildDate($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasBuildDate() => $_has(9);
  @$pb.TagNumber(10)
  void clearBuildDate() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get buildUser => $_getSZ(10);
  @$pb.TagNumber(11)
  set buildUser($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasBuildUser() => $_has(10);
  @$pb.TagNumber(11)
  void clearBuildUser() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get estimatedHeight => $_getI64(11);
  @$pb.TagNumber(12)
  set estimatedHeight($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasEstimatedHeight() => $_has(11);
  @$pb.TagNumber(12)
  void clearEstimatedHeight() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get zcashdBuild => $_getSZ(12);
  @$pb.TagNumber(13)
  set zcashdBuild($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasZcashdBuild() => $_has(12);
  @$pb.TagNumber(13)
  void clearZcashdBuild() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get zcashdSubversion => $_getSZ(13);
  @$pb.TagNumber(14)
  set zcashdSubversion($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasZcashdSubversion() => $_has(13);
  @$pb.TagNumber(14)
  void clearZcashdSubversion() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get donationAddress => $_getSZ(14);
  @$pb.TagNumber(15)
  set donationAddress($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasDonationAddress() => $_has(14);
  @$pb.TagNumber(15)
  void clearDonationAddress() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get upgradeName => $_getSZ(15);
  @$pb.TagNumber(16)
  set upgradeName($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasUpgradeName() => $_has(15);
  @$pb.TagNumber(16)
  void clearUpgradeName() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get upgradeHeight => $_getI64(16);
  @$pb.TagNumber(17)
  set upgradeHeight($fixnum.Int64 value) => $_setInt64(16, value);
  @$pb.TagNumber(17)
  $core.bool hasUpgradeHeight() => $_has(16);
  @$pb.TagNumber(17)
  void clearUpgradeHeight() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get lightwalletProtocolVersion => $_getSZ(17);
  @$pb.TagNumber(18)
  set lightwalletProtocolVersion($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasLightwalletProtocolVersion() => $_has(17);
  @$pb.TagNumber(18)
  void clearLightwalletProtocolVersion() => $_clearField(18);
}

/// TransparentAddressBlockFilter restricts the results of the GRPC methods that
/// use it to the transactions that involve the given address and were mined in
/// the specified block range. Non-default values for both the address and the
/// block range must be specified. Mempool transactions are not included.
///
/// The `poolTypes` field of the `range` argument should be ignored.
/// Implementations MAY consider it an error if any pool types are specified.
class TransparentAddressBlockFilter extends $pb.GeneratedMessage {
  factory TransparentAddressBlockFilter({
    $core.String? address,
    BlockRange? range,
  }) {
    final result = create();
    if (address != null) result.address = address;
    if (range != null) result.range = range;
    return result;
  }

  TransparentAddressBlockFilter._();

  factory TransparentAddressBlockFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TransparentAddressBlockFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TransparentAddressBlockFilter',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..aOM<BlockRange>(2, _omitFieldNames ? '' : 'range',
        subBuilder: BlockRange.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransparentAddressBlockFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransparentAddressBlockFilter copyWith(
          void Function(TransparentAddressBlockFilter) updates) =>
      super.copyWith(
              (message) => updates(message as TransparentAddressBlockFilter))
          as TransparentAddressBlockFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TransparentAddressBlockFilter create() =>
      TransparentAddressBlockFilter._();
  @$core.override
  TransparentAddressBlockFilter createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TransparentAddressBlockFilter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TransparentAddressBlockFilter>(create);
  static TransparentAddressBlockFilter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  BlockRange get range => $_getN(1);
  @$pb.TagNumber(2)
  set range(BlockRange value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRange() => $_has(1);
  @$pb.TagNumber(2)
  void clearRange() => $_clearField(2);
  @$pb.TagNumber(2)
  BlockRange ensureRange() => $_ensure(1);
}

/// Duration is currently used only for testing, so that the Ping rpc
/// can simulate a delay, to create many simultaneous connections. Units
/// are microseconds.
class Duration extends $pb.GeneratedMessage {
  factory Duration({
    $fixnum.Int64? intervalUs,
  }) {
    final result = create();
    if (intervalUs != null) result.intervalUs = intervalUs;
    return result;
  }

  Duration._();

  factory Duration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Duration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Duration',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'intervalUs', protoName: 'intervalUs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Duration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Duration copyWith(void Function(Duration) updates) =>
      super.copyWith((message) => updates(message as Duration)) as Duration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Duration create() => Duration._();
  @$core.override
  Duration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Duration getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Duration>(create);
  static Duration? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get intervalUs => $_getI64(0);
  @$pb.TagNumber(1)
  set intervalUs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIntervalUs() => $_has(0);
  @$pb.TagNumber(1)
  void clearIntervalUs() => $_clearField(1);
}

/// PingResponse is used to indicate concurrency, how many Ping rpcs
/// are executing upon entry and upon exit (after the delay).
/// This rpc is used for testing only.
class PingResponse extends $pb.GeneratedMessage {
  factory PingResponse({
    $fixnum.Int64? entry,
    $fixnum.Int64? exit,
  }) {
    final result = create();
    if (entry != null) result.entry = entry;
    if (exit != null) result.exit = exit;
    return result;
  }

  PingResponse._();

  factory PingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PingResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'entry')
    ..aInt64(2, _omitFieldNames ? '' : 'exit')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingResponse copyWith(void Function(PingResponse) updates) =>
      super.copyWith((message) => updates(message as PingResponse))
          as PingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PingResponse create() => PingResponse._();
  @$core.override
  PingResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PingResponse>(create);
  static PingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get entry => $_getI64(0);
  @$pb.TagNumber(1)
  set entry($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEntry() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntry() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get exit => $_getI64(1);
  @$pb.TagNumber(2)
  set exit($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExit() => $_has(1);
  @$pb.TagNumber(2)
  void clearExit() => $_clearField(2);
}

class Address extends $pb.GeneratedMessage {
  factory Address({
    $core.String? address,
  }) {
    final result = create();
    if (address != null) result.address = address;
    return result;
  }

  Address._();

  factory Address.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Address.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Address',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Address clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Address copyWith(void Function(Address) updates) =>
      super.copyWith((message) => updates(message as Address)) as Address;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Address create() => Address._();
  @$core.override
  Address createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Address getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Address>(create);
  static Address? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get address => $_getSZ(0);
  @$pb.TagNumber(1)
  set address($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearAddress() => $_clearField(1);
}

class AddressList extends $pb.GeneratedMessage {
  factory AddressList({
    $core.Iterable<$core.String>? addresses,
  }) {
    final result = create();
    if (addresses != null) result.addresses.addAll(addresses);
    return result;
  }

  AddressList._();

  factory AddressList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AddressList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AddressList',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'addresses')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddressList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddressList copyWith(void Function(AddressList) updates) =>
      super.copyWith((message) => updates(message as AddressList))
          as AddressList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AddressList create() => AddressList._();
  @$core.override
  AddressList createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AddressList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AddressList>(create);
  static AddressList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get addresses => $_getList(0);
}

class Balance extends $pb.GeneratedMessage {
  factory Balance({
    $fixnum.Int64? valueZat,
  }) {
    final result = create();
    if (valueZat != null) result.valueZat = valueZat;
    return result;
  }

  Balance._();

  factory Balance.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Balance.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Balance',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'valueZat', protoName: 'valueZat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Balance clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Balance copyWith(void Function(Balance) updates) =>
      super.copyWith((message) => updates(message as Balance)) as Balance;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Balance create() => Balance._();
  @$core.override
  Balance createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Balance getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Balance>(create);
  static Balance? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get valueZat => $_getI64(0);
  @$pb.TagNumber(1)
  set valueZat($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasValueZat() => $_has(0);
  @$pb.TagNumber(1)
  void clearValueZat() => $_clearField(1);
}

/// Request parameters for the `GetMempoolTx` RPC.
class GetMempoolTxRequest extends $pb.GeneratedMessage {
  factory GetMempoolTxRequest({
    $core.Iterable<$core.List<$core.int>>? excludeTxidSuffixes,
    $core.Iterable<PoolType>? poolTypes,
  }) {
    final result = create();
    if (excludeTxidSuffixes != null)
      result.excludeTxidSuffixes.addAll(excludeTxidSuffixes);
    if (poolTypes != null) result.poolTypes.addAll(poolTypes);
    return result;
  }

  GetMempoolTxRequest._();

  factory GetMempoolTxRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMempoolTxRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMempoolTxRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'excludeTxidSuffixes', $pb.PbFieldType.PY)
    ..pc<PoolType>(3, _omitFieldNames ? '' : 'poolTypes', $pb.PbFieldType.KE,
        protoName: 'poolTypes',
        valueOf: PoolType.valueOf,
        enumValues: PoolType.values,
        defaultEnumValue: PoolType.POOL_TYPE_INVALID)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMempoolTxRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMempoolTxRequest copyWith(void Function(GetMempoolTxRequest) updates) =>
      super.copyWith((message) => updates(message as GetMempoolTxRequest))
          as GetMempoolTxRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMempoolTxRequest create() => GetMempoolTxRequest._();
  @$core.override
  GetMempoolTxRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMempoolTxRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMempoolTxRequest>(create);
  static GetMempoolTxRequest? _defaultInstance;

  /// A list of transaction ID byte string suffixes that should be excluded
  /// from the response. These suffixes may be produced either directly from
  /// the underlying txid bytes, or, if the source values are encoded txid
  /// strings, by truncating the hexadecimal representation of each
  /// transaction ID to an even number of characters, and then hex-decoding
  /// and then byte-reversing this value to obtain the byte representation.
  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get excludeTxidSuffixes => $_getList(0);

  /// The server must prune `CompactTx`s returned to include only data
  /// relevant to the requested pool types. If no pool types are specified,
  /// the server should default to returning only data relevant to the shielded
  /// (Sapling, Orchard, and Ironwood) pools.
  @$pb.TagNumber(3)
  $pb.PbList<PoolType> get poolTypes => $_getList(1);
}

/// The TreeState is derived from the Zcash z_gettreestate rpc.
class TreeState extends $pb.GeneratedMessage {
  factory TreeState({
    $core.String? network,
    $fixnum.Int64? height,
    $core.String? hash,
    $core.int? time,
    $core.String? saplingTree,
    $core.String? orchardTree,
    $core.String? ironwoodTree,
  }) {
    final result = create();
    if (network != null) result.network = network;
    if (height != null) result.height = height;
    if (hash != null) result.hash = hash;
    if (time != null) result.time = time;
    if (saplingTree != null) result.saplingTree = saplingTree;
    if (orchardTree != null) result.orchardTree = orchardTree;
    if (ironwoodTree != null) result.ironwoodTree = ironwoodTree;
    return result;
  }

  TreeState._();

  factory TreeState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TreeState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TreeState',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'network')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'height', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'hash')
    ..aI(4, _omitFieldNames ? '' : 'time', fieldType: $pb.PbFieldType.OU3)
    ..aOS(5, _omitFieldNames ? '' : 'saplingTree', protoName: 'saplingTree')
    ..aOS(6, _omitFieldNames ? '' : 'orchardTree', protoName: 'orchardTree')
    ..aOS(7, _omitFieldNames ? '' : 'ironwoodTree', protoName: 'ironwoodTree')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TreeState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TreeState copyWith(void Function(TreeState) updates) =>
      super.copyWith((message) => updates(message as TreeState)) as TreeState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TreeState create() => TreeState._();
  @$core.override
  TreeState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TreeState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TreeState>(create);
  static TreeState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get network => $_getSZ(0);
  @$pb.TagNumber(1)
  set network($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNetwork() => $_has(0);
  @$pb.TagNumber(1)
  void clearNetwork() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get height => $_getI64(1);
  @$pb.TagNumber(2)
  set height($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeight() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get hash => $_getSZ(2);
  @$pb.TagNumber(3)
  set hash($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearHash() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get time => $_getIZ(3);
  @$pb.TagNumber(4)
  set time($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearTime() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get saplingTree => $_getSZ(4);
  @$pb.TagNumber(5)
  set saplingTree($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSaplingTree() => $_has(4);
  @$pb.TagNumber(5)
  void clearSaplingTree() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get orchardTree => $_getSZ(5);
  @$pb.TagNumber(6)
  set orchardTree($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOrchardTree() => $_has(5);
  @$pb.TagNumber(6)
  void clearOrchardTree() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get ironwoodTree => $_getSZ(6);
  @$pb.TagNumber(7)
  set ironwoodTree($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIronwoodTree() => $_has(6);
  @$pb.TagNumber(7)
  void clearIronwoodTree() => $_clearField(7);
}

class GetSubtreeRootsArg extends $pb.GeneratedMessage {
  factory GetSubtreeRootsArg({
    $core.int? startIndex,
    ShieldedProtocol? shieldedProtocol,
    $core.int? maxEntries,
  }) {
    final result = create();
    if (startIndex != null) result.startIndex = startIndex;
    if (shieldedProtocol != null) result.shieldedProtocol = shieldedProtocol;
    if (maxEntries != null) result.maxEntries = maxEntries;
    return result;
  }

  GetSubtreeRootsArg._();

  factory GetSubtreeRootsArg.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetSubtreeRootsArg.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetSubtreeRootsArg',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'startIndex',
        protoName: 'startIndex', fieldType: $pb.PbFieldType.OU3)
    ..aE<ShieldedProtocol>(2, _omitFieldNames ? '' : 'shieldedProtocol',
        protoName: 'shieldedProtocol', enumValues: ShieldedProtocol.values)
    ..aI(3, _omitFieldNames ? '' : 'maxEntries',
        protoName: 'maxEntries', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSubtreeRootsArg clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSubtreeRootsArg copyWith(void Function(GetSubtreeRootsArg) updates) =>
      super.copyWith((message) => updates(message as GetSubtreeRootsArg))
          as GetSubtreeRootsArg;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetSubtreeRootsArg create() => GetSubtreeRootsArg._();
  @$core.override
  GetSubtreeRootsArg createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetSubtreeRootsArg getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetSubtreeRootsArg>(create);
  static GetSubtreeRootsArg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get startIndex => $_getIZ(0);
  @$pb.TagNumber(1)
  set startIndex($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStartIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  ShieldedProtocol get shieldedProtocol => $_getN(1);
  @$pb.TagNumber(2)
  set shieldedProtocol(ShieldedProtocol value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasShieldedProtocol() => $_has(1);
  @$pb.TagNumber(2)
  void clearShieldedProtocol() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxEntries => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxEntries($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxEntries() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxEntries() => $_clearField(3);
}

class SubtreeRoot extends $pb.GeneratedMessage {
  factory SubtreeRoot({
    $core.List<$core.int>? rootHash,
    $core.List<$core.int>? completingBlockHash,
    $fixnum.Int64? completingBlockHeight,
  }) {
    final result = create();
    if (rootHash != null) result.rootHash = rootHash;
    if (completingBlockHash != null)
      result.completingBlockHash = completingBlockHash;
    if (completingBlockHeight != null)
      result.completingBlockHeight = completingBlockHeight;
    return result;
  }

  SubtreeRoot._();

  factory SubtreeRoot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SubtreeRoot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SubtreeRoot',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'rootHash', $pb.PbFieldType.OY,
        protoName: 'rootHash')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'completingBlockHash', $pb.PbFieldType.OY,
        protoName: 'completingBlockHash')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'completingBlockHeight', $pb.PbFieldType.OU6,
        protoName: 'completingBlockHeight', defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubtreeRoot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubtreeRoot copyWith(void Function(SubtreeRoot) updates) =>
      super.copyWith((message) => updates(message as SubtreeRoot))
          as SubtreeRoot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SubtreeRoot create() => SubtreeRoot._();
  @$core.override
  SubtreeRoot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SubtreeRoot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SubtreeRoot>(create);
  static SubtreeRoot? _defaultInstance;

  @$pb.TagNumber(2)
  $core.List<$core.int> get rootHash => $_getN(0);
  @$pb.TagNumber(2)
  set rootHash($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(2)
  $core.bool hasRootHash() => $_has(0);
  @$pb.TagNumber(2)
  void clearRootHash() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get completingBlockHash => $_getN(1);
  @$pb.TagNumber(3)
  set completingBlockHash($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(3)
  $core.bool hasCompletingBlockHash() => $_has(1);
  @$pb.TagNumber(3)
  void clearCompletingBlockHash() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get completingBlockHeight => $_getI64(2);
  @$pb.TagNumber(4)
  set completingBlockHeight($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(4)
  $core.bool hasCompletingBlockHeight() => $_has(2);
  @$pb.TagNumber(4)
  void clearCompletingBlockHeight() => $_clearField(4);
}

/// Results are sorted by height, which makes it easy to issue another
/// request that picks up from where the previous left off.
class GetAddressUtxosArg extends $pb.GeneratedMessage {
  factory GetAddressUtxosArg({
    $core.Iterable<$core.String>? addresses,
    $fixnum.Int64? startHeight,
    $core.int? maxEntries,
  }) {
    final result = create();
    if (addresses != null) result.addresses.addAll(addresses);
    if (startHeight != null) result.startHeight = startHeight;
    if (maxEntries != null) result.maxEntries = maxEntries;
    return result;
  }

  GetAddressUtxosArg._();

  factory GetAddressUtxosArg.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetAddressUtxosArg.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetAddressUtxosArg',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'addresses')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'startHeight', $pb.PbFieldType.OU6,
        protoName: 'startHeight', defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(3, _omitFieldNames ? '' : 'maxEntries',
        protoName: 'maxEntries', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetAddressUtxosArg clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetAddressUtxosArg copyWith(void Function(GetAddressUtxosArg) updates) =>
      super.copyWith((message) => updates(message as GetAddressUtxosArg))
          as GetAddressUtxosArg;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetAddressUtxosArg create() => GetAddressUtxosArg._();
  @$core.override
  GetAddressUtxosArg createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetAddressUtxosArg getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetAddressUtxosArg>(create);
  static GetAddressUtxosArg? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get addresses => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get startHeight => $_getI64(1);
  @$pb.TagNumber(2)
  set startHeight($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStartHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartHeight() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxEntries => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxEntries($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxEntries() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxEntries() => $_clearField(3);
}

class GetAddressUtxosReply extends $pb.GeneratedMessage {
  factory GetAddressUtxosReply({
    $core.List<$core.int>? txid,
    $core.int? index,
    $core.List<$core.int>? script,
    $fixnum.Int64? valueZat,
    $fixnum.Int64? height,
    $core.String? address,
  }) {
    final result = create();
    if (txid != null) result.txid = txid;
    if (index != null) result.index = index;
    if (script != null) result.script = script;
    if (valueZat != null) result.valueZat = valueZat;
    if (height != null) result.height = height;
    if (address != null) result.address = address;
    return result;
  }

  GetAddressUtxosReply._();

  factory GetAddressUtxosReply.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetAddressUtxosReply.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetAddressUtxosReply',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'txid', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'index')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'script', $pb.PbFieldType.OY)
    ..aInt64(4, _omitFieldNames ? '' : 'valueZat', protoName: 'valueZat')
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'height', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(6, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetAddressUtxosReply clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetAddressUtxosReply copyWith(void Function(GetAddressUtxosReply) updates) =>
      super.copyWith((message) => updates(message as GetAddressUtxosReply))
          as GetAddressUtxosReply;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetAddressUtxosReply create() => GetAddressUtxosReply._();
  @$core.override
  GetAddressUtxosReply createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetAddressUtxosReply getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetAddressUtxosReply>(create);
  static GetAddressUtxosReply? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get txid => $_getN(0);
  @$pb.TagNumber(1)
  set txid($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTxid() => $_has(0);
  @$pb.TagNumber(1)
  void clearTxid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get index => $_getIZ(1);
  @$pb.TagNumber(2)
  set index($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndex() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get script => $_getN(2);
  @$pb.TagNumber(3)
  set script($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasScript() => $_has(2);
  @$pb.TagNumber(3)
  void clearScript() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get valueZat => $_getI64(3);
  @$pb.TagNumber(4)
  set valueZat($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasValueZat() => $_has(3);
  @$pb.TagNumber(4)
  void clearValueZat() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get height => $_getI64(4);
  @$pb.TagNumber(5)
  set height($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeight() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeight() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get address => $_getSZ(5);
  @$pb.TagNumber(6)
  set address($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAddress() => $_has(5);
  @$pb.TagNumber(6)
  void clearAddress() => $_clearField(6);
}

class GetAddressUtxosReplyList extends $pb.GeneratedMessage {
  factory GetAddressUtxosReplyList({
    $core.Iterable<GetAddressUtxosReply>? addressUtxos,
  }) {
    final result = create();
    if (addressUtxos != null) result.addressUtxos.addAll(addressUtxos);
    return result;
  }

  GetAddressUtxosReplyList._();

  factory GetAddressUtxosReplyList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetAddressUtxosReplyList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetAddressUtxosReplyList',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..pPM<GetAddressUtxosReply>(1, _omitFieldNames ? '' : 'addressUtxos',
        protoName: 'addressUtxos', subBuilder: GetAddressUtxosReply.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetAddressUtxosReplyList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetAddressUtxosReplyList copyWith(
          void Function(GetAddressUtxosReplyList) updates) =>
      super.copyWith((message) => updates(message as GetAddressUtxosReplyList))
          as GetAddressUtxosReplyList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetAddressUtxosReplyList create() => GetAddressUtxosReplyList._();
  @$core.override
  GetAddressUtxosReplyList createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetAddressUtxosReplyList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetAddressUtxosReplyList>(create);
  static GetAddressUtxosReplyList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<GetAddressUtxosReply> get addressUtxos => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
