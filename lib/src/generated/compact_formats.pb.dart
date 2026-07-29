// This is a generated file - do not edit.
//
// Generated from compact_formats.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Information about the state of the chain as of a given block.
class ChainMetadata extends $pb.GeneratedMessage {
  factory ChainMetadata({
    $core.int? saplingCommitmentTreeSize,
    $core.int? orchardCommitmentTreeSize,
    $core.int? ironwoodCommitmentTreeSize,
  }) {
    final result = create();
    if (saplingCommitmentTreeSize != null)
      result.saplingCommitmentTreeSize = saplingCommitmentTreeSize;
    if (orchardCommitmentTreeSize != null)
      result.orchardCommitmentTreeSize = orchardCommitmentTreeSize;
    if (ironwoodCommitmentTreeSize != null)
      result.ironwoodCommitmentTreeSize = ironwoodCommitmentTreeSize;
    return result;
  }

  ChainMetadata._();

  factory ChainMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChainMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChainMetadata',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'saplingCommitmentTreeSize',
        protoName: 'saplingCommitmentTreeSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'orchardCommitmentTreeSize',
        protoName: 'orchardCommitmentTreeSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'ironwoodCommitmentTreeSize',
        protoName: 'ironwoodCommitmentTreeSize', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChainMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChainMetadata copyWith(void Function(ChainMetadata) updates) =>
      super.copyWith((message) => updates(message as ChainMetadata))
          as ChainMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChainMetadata create() => ChainMetadata._();
  @$core.override
  ChainMetadata createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChainMetadata getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChainMetadata>(create);
  static ChainMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get saplingCommitmentTreeSize => $_getIZ(0);
  @$pb.TagNumber(1)
  set saplingCommitmentTreeSize($core.int value) =>
      $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSaplingCommitmentTreeSize() => $_has(0);
  @$pb.TagNumber(1)
  void clearSaplingCommitmentTreeSize() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get orchardCommitmentTreeSize => $_getIZ(1);
  @$pb.TagNumber(2)
  set orchardCommitmentTreeSize($core.int value) =>
      $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOrchardCommitmentTreeSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearOrchardCommitmentTreeSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get ironwoodCommitmentTreeSize => $_getIZ(2);
  @$pb.TagNumber(3)
  set ironwoodCommitmentTreeSize($core.int value) =>
      $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIronwoodCommitmentTreeSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearIronwoodCommitmentTreeSize() => $_clearField(3);
}

/// A compact representation of a Zcash block.
///
/// CompactBlock is a packaging of ONLY the data from a block that's needed to:
///   1. Detect a payment to your Shielded address
///   2. Detect a spend of your Shielded notes
///   3. Update your witnesses to generate new spend proofs.
///   4. Spend UTXOs associated to t-addresses of your wallet.
///
/// Currently, the `header` field should always be unset (empty). In the future,
/// the presence or absence of header data may be made dependent on request
/// parameters, although it is likely that such flexibility will only be provided via
/// newly-added service methods, not via existing APIs.
class CompactBlock extends $pb.GeneratedMessage {
  factory CompactBlock({
    $core.int? protoVersion,
    $fixnum.Int64? height,
    $core.List<$core.int>? hash,
    $core.List<$core.int>? prevHash,
    $core.int? time,
    $core.List<$core.int>? header,
    $core.Iterable<CompactTx>? vtx,
    ChainMetadata? chainMetadata,
  }) {
    final result = create();
    if (protoVersion != null) result.protoVersion = protoVersion;
    if (height != null) result.height = height;
    if (hash != null) result.hash = hash;
    if (prevHash != null) result.prevHash = prevHash;
    if (time != null) result.time = time;
    if (header != null) result.header = header;
    if (vtx != null) result.vtx.addAll(vtx);
    if (chainMetadata != null) result.chainMetadata = chainMetadata;
    return result;
  }

  CompactBlock._();

  factory CompactBlock.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CompactBlock.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompactBlock',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'protoVersion',
        protoName: 'protoVersion', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'height', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'hash', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'prevHash', $pb.PbFieldType.OY,
        protoName: 'prevHash')
    ..aI(5, _omitFieldNames ? '' : 'time', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'header', $pb.PbFieldType.OY)
    ..pPM<CompactTx>(7, _omitFieldNames ? '' : 'vtx',
        subBuilder: CompactTx.create)
    ..aOM<ChainMetadata>(8, _omitFieldNames ? '' : 'chainMetadata',
        protoName: 'chainMetadata', subBuilder: ChainMetadata.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactBlock clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactBlock copyWith(void Function(CompactBlock) updates) =>
      super.copyWith((message) => updates(message as CompactBlock))
          as CompactBlock;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompactBlock create() => CompactBlock._();
  @$core.override
  CompactBlock createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CompactBlock getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompactBlock>(create);
  static CompactBlock? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protoVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protoVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtoVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtoVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get height => $_getI64(1);
  @$pb.TagNumber(2)
  set height($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeight() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get hash => $_getN(2);
  @$pb.TagNumber(3)
  set hash($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearHash() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get prevHash => $_getN(3);
  @$pb.TagNumber(4)
  set prevHash($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPrevHash() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrevHash() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get time => $_getIZ(4);
  @$pb.TagNumber(5)
  set time($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTime() => $_has(4);
  @$pb.TagNumber(5)
  void clearTime() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get header => $_getN(5);
  @$pb.TagNumber(6)
  set header($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHeader() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeader() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<CompactTx> get vtx => $_getList(6);

  @$pb.TagNumber(8)
  ChainMetadata get chainMetadata => $_getN(7);
  @$pb.TagNumber(8)
  set chainMetadata(ChainMetadata value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasChainMetadata() => $_has(7);
  @$pb.TagNumber(8)
  void clearChainMetadata() => $_clearField(8);
  @$pb.TagNumber(8)
  ChainMetadata ensureChainMetadata() => $_ensure(7);
}

/// A compact representation of a Zcash transaction.
///
/// CompactTx contains the minimum information for a wallet to know if this transaction
/// is relevant to it (either pays to it or spends from it) via shielded elements. Additionally,
/// it can optionally include the minimum necessary data to detect payments to transparent addresses
/// related to your wallet.
class CompactTx extends $pb.GeneratedMessage {
  factory CompactTx({
    $fixnum.Int64? index,
    $core.List<$core.int>? txid,
    $core.int? fee,
    $core.Iterable<CompactSaplingSpend>? spends,
    $core.Iterable<CompactSaplingOutput>? outputs,
    $core.Iterable<CompactOrchardAction>? actions,
    $core.Iterable<CompactTxIn>? vin,
    $core.Iterable<TxOut>? vout,
    $core.Iterable<CompactOrchardAction>? ironwoodActions,
  }) {
    final result = create();
    if (index != null) result.index = index;
    if (txid != null) result.txid = txid;
    if (fee != null) result.fee = fee;
    if (spends != null) result.spends.addAll(spends);
    if (outputs != null) result.outputs.addAll(outputs);
    if (actions != null) result.actions.addAll(actions);
    if (vin != null) result.vin.addAll(vin);
    if (vout != null) result.vout.addAll(vout);
    if (ironwoodActions != null) result.ironwoodActions.addAll(ironwoodActions);
    return result;
  }

  CompactTx._();

  factory CompactTx.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CompactTx.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompactTx',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'index', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'txid', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'fee', fieldType: $pb.PbFieldType.OU3)
    ..pPM<CompactSaplingSpend>(4, _omitFieldNames ? '' : 'spends',
        subBuilder: CompactSaplingSpend.create)
    ..pPM<CompactSaplingOutput>(5, _omitFieldNames ? '' : 'outputs',
        subBuilder: CompactSaplingOutput.create)
    ..pPM<CompactOrchardAction>(6, _omitFieldNames ? '' : 'actions',
        subBuilder: CompactOrchardAction.create)
    ..pPM<CompactTxIn>(7, _omitFieldNames ? '' : 'vin',
        subBuilder: CompactTxIn.create)
    ..pPM<TxOut>(8, _omitFieldNames ? '' : 'vout', subBuilder: TxOut.create)
    ..pPM<CompactOrchardAction>(9, _omitFieldNames ? '' : 'ironwoodActions',
        protoName: 'ironwoodActions', subBuilder: CompactOrchardAction.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactTx clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactTx copyWith(void Function(CompactTx) updates) =>
      super.copyWith((message) => updates(message as CompactTx)) as CompactTx;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompactTx create() => CompactTx._();
  @$core.override
  CompactTx createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CompactTx getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CompactTx>(create);
  static CompactTx? _defaultInstance;

  /// The index of the transaction within the block.
  @$pb.TagNumber(1)
  $fixnum.Int64 get index => $_getI64(0);
  @$pb.TagNumber(1)
  set index($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  /// The id of the transaction as defined in
  /// [§ 7.1.1 ‘Transaction Identifiers’](https://zips.z.cash/protocol/protocol.pdf#txnidentifiers)
  /// This byte array MUST be in protocol order and MUST NOT be reversed
  /// or hex-encoded; the byte-reversed and hex-encoded representation is
  /// exclusively a textual representation of a txid.
  @$pb.TagNumber(2)
  $core.List<$core.int> get txid => $_getN(1);
  @$pb.TagNumber(2)
  set txid($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTxid() => $_has(1);
  @$pb.TagNumber(2)
  void clearTxid() => $_clearField(2);

  /// The transaction fee: present if server can provide. In the case of a
  /// stateless server and a transaction with transparent inputs, this will be
  /// unset because the calculation requires reference to prior transactions.
  /// If there are no transparent inputs, the fee will be calculable as:
  ///    valueBalanceSapling + valueBalanceOrchard + valueBalanceIronwood
  ///    + sum(vPubNew) - sum(vPubOld) - sum(tOut)
  @$pb.TagNumber(3)
  $core.int get fee => $_getIZ(2);
  @$pb.TagNumber(3)
  set fee($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFee() => $_has(2);
  @$pb.TagNumber(3)
  void clearFee() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<CompactSaplingSpend> get spends => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<CompactSaplingOutput> get outputs => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<CompactOrchardAction> get actions => $_getList(5);

  /// `CompactTxIn` values corresponding to the `vin` entries of the full transaction.
  ///
  /// Note: the single null-outpoint input for coinbase transactions is omitted. Light
  /// clients can test `CompactTx.index == 0` to determine whether a `CompactTx`
  /// represents a coinbase transaction, as the coinbase transaction is always the
  /// first transaction in any block.
  @$pb.TagNumber(7)
  $pb.PbList<CompactTxIn> get vin => $_getList(6);

  /// A sequence of transparent outputs being created by the transaction.
  @$pb.TagNumber(8)
  $pb.PbList<TxOut> get vout => $_getList(7);

  /// A sequence of Ironwood actions in the transaction. Ironwood reuses the
  /// compact Orchard action shape because the pools have identical action fields.
  @$pb.TagNumber(9)
  $pb.PbList<CompactOrchardAction> get ironwoodActions => $_getList(8);
}

/// A compact representation of a transparent transaction input.
class CompactTxIn extends $pb.GeneratedMessage {
  factory CompactTxIn({
    $core.List<$core.int>? prevoutTxid,
    $core.int? prevoutIndex,
  }) {
    final result = create();
    if (prevoutTxid != null) result.prevoutTxid = prevoutTxid;
    if (prevoutIndex != null) result.prevoutIndex = prevoutIndex;
    return result;
  }

  CompactTxIn._();

  factory CompactTxIn.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CompactTxIn.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompactTxIn',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'prevoutTxid', $pb.PbFieldType.OY,
        protoName: 'prevoutTxid')
    ..aI(2, _omitFieldNames ? '' : 'prevoutIndex',
        protoName: 'prevoutIndex', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactTxIn clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactTxIn copyWith(void Function(CompactTxIn) updates) =>
      super.copyWith((message) => updates(message as CompactTxIn))
          as CompactTxIn;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompactTxIn create() => CompactTxIn._();
  @$core.override
  CompactTxIn createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CompactTxIn getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompactTxIn>(create);
  static CompactTxIn? _defaultInstance;

  /// The id of the transaction that generated the output being spent. This
  /// byte array must be in protocol order and MUST NOT be reversed or
  /// hex-encoded.
  @$pb.TagNumber(1)
  $core.List<$core.int> get prevoutTxid => $_getN(0);
  @$pb.TagNumber(1)
  set prevoutTxid($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPrevoutTxid() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrevoutTxid() => $_clearField(1);

  /// The index of the output being spent in the `vout` array of the
  /// transaction referred to by `prevoutTxid`.
  @$pb.TagNumber(2)
  $core.int get prevoutIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set prevoutIndex($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPrevoutIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrevoutIndex() => $_clearField(2);
}

/// A transparent output being created by the transaction.
///
/// This contains identical data to the `TxOut` type in the transaction itself, and
/// thus it is not "compact".
class TxOut extends $pb.GeneratedMessage {
  factory TxOut({
    $fixnum.Int64? value,
    $core.List<$core.int>? scriptPubKey,
  }) {
    final result = create();
    if (value != null) result.value = value;
    if (scriptPubKey != null) result.scriptPubKey = scriptPubKey;
    return result;
  }

  TxOut._();

  factory TxOut.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TxOut.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TxOut',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'value', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'scriptPubKey', $pb.PbFieldType.OY,
        protoName: 'scriptPubKey')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TxOut clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TxOut copyWith(void Function(TxOut) updates) =>
      super.copyWith((message) => updates(message as TxOut)) as TxOut;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TxOut create() => TxOut._();
  @$core.override
  TxOut createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TxOut getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TxOut>(create);
  static TxOut? _defaultInstance;

  /// The value of the output, in Zatoshis.
  @$pb.TagNumber(1)
  $fixnum.Int64 get value => $_getI64(0);
  @$pb.TagNumber(1)
  set value($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => $_clearField(1);

  /// The script pubkey that must be satisfied in order to spend this output.
  @$pb.TagNumber(2)
  $core.List<$core.int> get scriptPubKey => $_getN(1);
  @$pb.TagNumber(2)
  set scriptPubKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScriptPubKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearScriptPubKey() => $_clearField(2);
}

/// A compact representation of a [Sapling Spend](https://zips.z.cash/protocol/protocol.pdf#spendencodingandconsensus).
///
/// CompactSaplingSpend is a Sapling Spend Description as described in 7.3 of the Zcash
/// protocol specification.
class CompactSaplingSpend extends $pb.GeneratedMessage {
  factory CompactSaplingSpend({
    $core.List<$core.int>? nf,
  }) {
    final result = create();
    if (nf != null) result.nf = nf;
    return result;
  }

  CompactSaplingSpend._();

  factory CompactSaplingSpend.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CompactSaplingSpend.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompactSaplingSpend',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nf', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactSaplingSpend clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactSaplingSpend copyWith(void Function(CompactSaplingSpend) updates) =>
      super.copyWith((message) => updates(message as CompactSaplingSpend))
          as CompactSaplingSpend;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompactSaplingSpend create() => CompactSaplingSpend._();
  @$core.override
  CompactSaplingSpend createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CompactSaplingSpend getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompactSaplingSpend>(create);
  static CompactSaplingSpend? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nf => $_getN(0);
  @$pb.TagNumber(1)
  set nf($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNf() => $_has(0);
  @$pb.TagNumber(1)
  void clearNf() => $_clearField(1);
}

/// A compact representation of a [Sapling Output](https://zips.z.cash/protocol/protocol.pdf#outputencodingandconsensus).
///
/// It encodes the `cmu` field, `ephemeralKey` field, and a 52-byte prefix of the
/// `encCiphertext` field of a Sapling Output Description. Total size is 116 bytes.
class CompactSaplingOutput extends $pb.GeneratedMessage {
  factory CompactSaplingOutput({
    $core.List<$core.int>? cmu,
    $core.List<$core.int>? ephemeralKey,
    $core.List<$core.int>? ciphertext,
  }) {
    final result = create();
    if (cmu != null) result.cmu = cmu;
    if (ephemeralKey != null) result.ephemeralKey = ephemeralKey;
    if (ciphertext != null) result.ciphertext = ciphertext;
    return result;
  }

  CompactSaplingOutput._();

  factory CompactSaplingOutput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CompactSaplingOutput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompactSaplingOutput',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'cmu', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ephemeralKey', $pb.PbFieldType.OY,
        protoName: 'ephemeralKey')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'ciphertext', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactSaplingOutput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactSaplingOutput copyWith(void Function(CompactSaplingOutput) updates) =>
      super.copyWith((message) => updates(message as CompactSaplingOutput))
          as CompactSaplingOutput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompactSaplingOutput create() => CompactSaplingOutput._();
  @$core.override
  CompactSaplingOutput createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CompactSaplingOutput getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompactSaplingOutput>(create);
  static CompactSaplingOutput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get cmu => $_getN(0);
  @$pb.TagNumber(1)
  set cmu($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCmu() => $_has(0);
  @$pb.TagNumber(1)
  void clearCmu() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ephemeralKey => $_getN(1);
  @$pb.TagNumber(2)
  set ephemeralKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEphemeralKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearEphemeralKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ciphertext => $_getN(2);
  @$pb.TagNumber(3)
  set ciphertext($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCiphertext() => $_has(2);
  @$pb.TagNumber(3)
  void clearCiphertext() => $_clearField(3);
}

/// A compact representation of an [Orchard Action](https://zips.z.cash/protocol/protocol.pdf#actionencodingandconsensus).
///
/// This shape is also used for Ironwood actions because Ironwood action fields
/// are identical to Orchard action fields.
class CompactOrchardAction extends $pb.GeneratedMessage {
  factory CompactOrchardAction({
    $core.List<$core.int>? nullifier,
    $core.List<$core.int>? cmx,
    $core.List<$core.int>? ephemeralKey,
    $core.List<$core.int>? ciphertext,
  }) {
    final result = create();
    if (nullifier != null) result.nullifier = nullifier;
    if (cmx != null) result.cmx = cmx;
    if (ephemeralKey != null) result.ephemeralKey = ephemeralKey;
    if (ciphertext != null) result.ciphertext = ciphertext;
    return result;
  }

  CompactOrchardAction._();

  factory CompactOrchardAction.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CompactOrchardAction.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompactOrchardAction',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'cash.z.wallet.sdk.rpc'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nullifier', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'cmx', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'ephemeralKey', $pb.PbFieldType.OY,
        protoName: 'ephemeralKey')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'ciphertext', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactOrchardAction clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompactOrchardAction copyWith(void Function(CompactOrchardAction) updates) =>
      super.copyWith((message) => updates(message as CompactOrchardAction))
          as CompactOrchardAction;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CompactOrchardAction create() => CompactOrchardAction._();
  @$core.override
  CompactOrchardAction createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CompactOrchardAction getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompactOrchardAction>(create);
  static CompactOrchardAction? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nullifier => $_getN(0);
  @$pb.TagNumber(1)
  set nullifier($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNullifier() => $_has(0);
  @$pb.TagNumber(1)
  void clearNullifier() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get cmx => $_getN(1);
  @$pb.TagNumber(2)
  set cmx($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCmx() => $_has(1);
  @$pb.TagNumber(2)
  void clearCmx() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ephemeralKey => $_getN(2);
  @$pb.TagNumber(3)
  set ephemeralKey($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEphemeralKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearEphemeralKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ciphertext => $_getN(3);
  @$pb.TagNumber(4)
  set ciphertext($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCiphertext() => $_has(3);
  @$pb.TagNumber(4)
  void clearCiphertext() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
