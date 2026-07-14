// This is a generated file - do not edit.
//
// Generated from service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use poolTypeDescriptor instead')
const PoolType$json = {
  '1': 'PoolType',
  '2': [
    {'1': 'POOL_TYPE_INVALID', '2': 0},
    {'1': 'TRANSPARENT', '2': 1},
    {'1': 'SAPLING', '2': 2},
    {'1': 'ORCHARD', '2': 3},
    {'1': 'IRONWOOD', '2': 4},
  ],
};

/// Descriptor for `PoolType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List poolTypeDescriptor = $convert.base64Decode(
    'CghQb29sVHlwZRIVChFQT09MX1RZUEVfSU5WQUxJRBAAEg8KC1RSQU5TUEFSRU5UEAESCwoHU0'
    'FQTElORxACEgsKB09SQ0hBUkQQAxIMCghJUk9OV09PRBAE');

@$core.Deprecated('Use shieldedProtocolDescriptor instead')
const ShieldedProtocol$json = {
  '1': 'ShieldedProtocol',
  '2': [
    {'1': 'sapling', '2': 0},
    {'1': 'orchard', '2': 1},
    {'1': 'ironwood', '2': 2},
  ],
};

/// Descriptor for `ShieldedProtocol`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List shieldedProtocolDescriptor = $convert.base64Decode(
    'ChBTaGllbGRlZFByb3RvY29sEgsKB3NhcGxpbmcQABILCgdvcmNoYXJkEAESDAoIaXJvbndvb2'
    'QQAg==');

@$core.Deprecated('Use blockIDDescriptor instead')
const BlockID$json = {
  '1': 'BlockID',
  '2': [
    {'1': 'height', '3': 1, '4': 1, '5': 4, '10': 'height'},
    {'1': 'hash', '3': 2, '4': 1, '5': 12, '10': 'hash'},
  ],
};

/// Descriptor for `BlockID`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List blockIDDescriptor = $convert.base64Decode(
    'CgdCbG9ja0lEEhYKBmhlaWdodBgBIAEoBFIGaGVpZ2h0EhIKBGhhc2gYAiABKAxSBGhhc2g=');

@$core.Deprecated('Use blockRangeDescriptor instead')
const BlockRange$json = {
  '1': 'BlockRange',
  '2': [
    {
      '1': 'start',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.BlockID',
      '10': 'start'
    },
    {
      '1': 'end',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.BlockID',
      '10': 'end'
    },
    {
      '1': 'poolTypes',
      '3': 3,
      '4': 3,
      '5': 14,
      '6': '.cash.z.wallet.sdk.rpc.PoolType',
      '10': 'poolTypes'
    },
  ],
};

/// Descriptor for `BlockRange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List blockRangeDescriptor = $convert.base64Decode(
    'CgpCbG9ja1JhbmdlEjQKBXN0YXJ0GAEgASgLMh4uY2FzaC56LndhbGxldC5zZGsucnBjLkJsb2'
    'NrSURSBXN0YXJ0EjAKA2VuZBgCIAEoCzIeLmNhc2guei53YWxsZXQuc2RrLnJwYy5CbG9ja0lE'
    'UgNlbmQSPQoJcG9vbFR5cGVzGAMgAygOMh8uY2FzaC56LndhbGxldC5zZGsucnBjLlBvb2xUeX'
    'BlUglwb29sVHlwZXM=');

@$core.Deprecated('Use txFilterDescriptor instead')
const TxFilter$json = {
  '1': 'TxFilter',
  '2': [
    {
      '1': 'block',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.BlockID',
      '10': 'block'
    },
    {'1': 'index', '3': 2, '4': 1, '5': 4, '10': 'index'},
    {'1': 'hash', '3': 3, '4': 1, '5': 12, '10': 'hash'},
  ],
};

/// Descriptor for `TxFilter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List txFilterDescriptor = $convert.base64Decode(
    'CghUeEZpbHRlchI0CgVibG9jaxgBIAEoCzIeLmNhc2guei53YWxsZXQuc2RrLnJwYy5CbG9ja0'
    'lEUgVibG9jaxIUCgVpbmRleBgCIAEoBFIFaW5kZXgSEgoEaGFzaBgDIAEoDFIEaGFzaA==');

@$core.Deprecated('Use rawTransactionDescriptor instead')
const RawTransaction$json = {
  '1': 'RawTransaction',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'height', '3': 2, '4': 1, '5': 4, '10': 'height'},
  ],
};

/// Descriptor for `RawTransaction`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rawTransactionDescriptor = $convert.base64Decode(
    'Cg5SYXdUcmFuc2FjdGlvbhISCgRkYXRhGAEgASgMUgRkYXRhEhYKBmhlaWdodBgCIAEoBFIGaG'
    'VpZ2h0');

@$core.Deprecated('Use sendResponseDescriptor instead')
const SendResponse$json = {
  '1': 'SendResponse',
  '2': [
    {'1': 'errorCode', '3': 1, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'errorMessage', '3': 2, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `SendResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendResponseDescriptor = $convert.base64Decode(
    'CgxTZW5kUmVzcG9uc2USHAoJZXJyb3JDb2RlGAEgASgFUgllcnJvckNvZGUSIgoMZXJyb3JNZX'
    'NzYWdlGAIgASgJUgxlcnJvck1lc3NhZ2U=');

@$core.Deprecated('Use chainSpecDescriptor instead')
const ChainSpec$json = {
  '1': 'ChainSpec',
};

/// Descriptor for `ChainSpec`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chainSpecDescriptor =
    $convert.base64Decode('CglDaGFpblNwZWM=');

@$core.Deprecated('Use emptyDescriptor instead')
const Empty$json = {
  '1': 'Empty',
};

/// Descriptor for `Empty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emptyDescriptor =
    $convert.base64Decode('CgVFbXB0eQ==');

@$core.Deprecated('Use lightdInfoDescriptor instead')
const LightdInfo$json = {
  '1': 'LightdInfo',
  '2': [
    {'1': 'version', '3': 1, '4': 1, '5': 9, '10': 'version'},
    {'1': 'vendor', '3': 2, '4': 1, '5': 9, '10': 'vendor'},
    {'1': 'taddrSupport', '3': 3, '4': 1, '5': 8, '10': 'taddrSupport'},
    {'1': 'chainName', '3': 4, '4': 1, '5': 9, '10': 'chainName'},
    {
      '1': 'saplingActivationHeight',
      '3': 5,
      '4': 1,
      '5': 4,
      '10': 'saplingActivationHeight'
    },
    {
      '1': 'consensusBranchId',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'consensusBranchId'
    },
    {'1': 'blockHeight', '3': 7, '4': 1, '5': 4, '10': 'blockHeight'},
    {'1': 'gitCommit', '3': 8, '4': 1, '5': 9, '10': 'gitCommit'},
    {'1': 'branch', '3': 9, '4': 1, '5': 9, '10': 'branch'},
    {'1': 'buildDate', '3': 10, '4': 1, '5': 9, '10': 'buildDate'},
    {'1': 'buildUser', '3': 11, '4': 1, '5': 9, '10': 'buildUser'},
    {'1': 'estimatedHeight', '3': 12, '4': 1, '5': 4, '10': 'estimatedHeight'},
    {'1': 'zcashdBuild', '3': 13, '4': 1, '5': 9, '10': 'zcashdBuild'},
    {
      '1': 'zcashdSubversion',
      '3': 14,
      '4': 1,
      '5': 9,
      '10': 'zcashdSubversion'
    },
    {'1': 'donationAddress', '3': 15, '4': 1, '5': 9, '10': 'donationAddress'},
    {'1': 'upgradeName', '3': 16, '4': 1, '5': 9, '10': 'upgradeName'},
    {'1': 'upgradeHeight', '3': 17, '4': 1, '5': 4, '10': 'upgradeHeight'},
    {
      '1': 'lightwalletProtocolVersion',
      '3': 18,
      '4': 1,
      '5': 9,
      '10': 'lightwalletProtocolVersion'
    },
  ],
};

/// Descriptor for `LightdInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lightdInfoDescriptor = $convert.base64Decode(
    'CgpMaWdodGRJbmZvEhgKB3ZlcnNpb24YASABKAlSB3ZlcnNpb24SFgoGdmVuZG9yGAIgASgJUg'
    'Z2ZW5kb3ISIgoMdGFkZHJTdXBwb3J0GAMgASgIUgx0YWRkclN1cHBvcnQSHAoJY2hhaW5OYW1l'
    'GAQgASgJUgljaGFpbk5hbWUSOAoXc2FwbGluZ0FjdGl2YXRpb25IZWlnaHQYBSABKARSF3NhcG'
    'xpbmdBY3RpdmF0aW9uSGVpZ2h0EiwKEWNvbnNlbnN1c0JyYW5jaElkGAYgASgJUhFjb25zZW5z'
    'dXNCcmFuY2hJZBIgCgtibG9ja0hlaWdodBgHIAEoBFILYmxvY2tIZWlnaHQSHAoJZ2l0Q29tbW'
    'l0GAggASgJUglnaXRDb21taXQSFgoGYnJhbmNoGAkgASgJUgZicmFuY2gSHAoJYnVpbGREYXRl'
    'GAogASgJUglidWlsZERhdGUSHAoJYnVpbGRVc2VyGAsgASgJUglidWlsZFVzZXISKAoPZXN0aW'
    '1hdGVkSGVpZ2h0GAwgASgEUg9lc3RpbWF0ZWRIZWlnaHQSIAoLemNhc2hkQnVpbGQYDSABKAlS'
    'C3pjYXNoZEJ1aWxkEioKEHpjYXNoZFN1YnZlcnNpb24YDiABKAlSEHpjYXNoZFN1YnZlcnNpb2'
    '4SKAoPZG9uYXRpb25BZGRyZXNzGA8gASgJUg9kb25hdGlvbkFkZHJlc3MSIAoLdXBncmFkZU5h'
    'bWUYECABKAlSC3VwZ3JhZGVOYW1lEiQKDXVwZ3JhZGVIZWlnaHQYESABKARSDXVwZ3JhZGVIZW'
    'lnaHQSPgoabGlnaHR3YWxsZXRQcm90b2NvbFZlcnNpb24YEiABKAlSGmxpZ2h0d2FsbGV0UHJv'
    'dG9jb2xWZXJzaW9u');

@$core.Deprecated('Use transparentAddressBlockFilterDescriptor instead')
const TransparentAddressBlockFilter$json = {
  '1': 'TransparentAddressBlockFilter',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
    {
      '1': 'range',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.BlockRange',
      '10': 'range'
    },
  ],
};

/// Descriptor for `TransparentAddressBlockFilter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transparentAddressBlockFilterDescriptor =
    $convert.base64Decode(
        'Ch1UcmFuc3BhcmVudEFkZHJlc3NCbG9ja0ZpbHRlchIYCgdhZGRyZXNzGAEgASgJUgdhZGRyZX'
        'NzEjcKBXJhbmdlGAIgASgLMiEuY2FzaC56LndhbGxldC5zZGsucnBjLkJsb2NrUmFuZ2VSBXJh'
        'bmdl');

@$core.Deprecated('Use durationDescriptor instead')
const Duration$json = {
  '1': 'Duration',
  '2': [
    {'1': 'intervalUs', '3': 1, '4': 1, '5': 3, '10': 'intervalUs'},
  ],
};

/// Descriptor for `Duration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List durationDescriptor = $convert
    .base64Decode('CghEdXJhdGlvbhIeCgppbnRlcnZhbFVzGAEgASgDUgppbnRlcnZhbFVz');

@$core.Deprecated('Use pingResponseDescriptor instead')
const PingResponse$json = {
  '1': 'PingResponse',
  '2': [
    {'1': 'entry', '3': 1, '4': 1, '5': 3, '10': 'entry'},
    {'1': 'exit', '3': 2, '4': 1, '5': 3, '10': 'exit'},
  ],
};

/// Descriptor for `PingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingResponseDescriptor = $convert.base64Decode(
    'CgxQaW5nUmVzcG9uc2USFAoFZW50cnkYASABKANSBWVudHJ5EhIKBGV4aXQYAiABKANSBGV4aX'
    'Q=');

@$core.Deprecated('Use addressDescriptor instead')
const Address$json = {
  '1': 'Address',
  '2': [
    {'1': 'address', '3': 1, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `Address`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addressDescriptor =
    $convert.base64Decode('CgdBZGRyZXNzEhgKB2FkZHJlc3MYASABKAlSB2FkZHJlc3M=');

@$core.Deprecated('Use addressListDescriptor instead')
const AddressList$json = {
  '1': 'AddressList',
  '2': [
    {'1': 'addresses', '3': 1, '4': 3, '5': 9, '10': 'addresses'},
  ],
};

/// Descriptor for `AddressList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addressListDescriptor = $convert.base64Decode(
    'CgtBZGRyZXNzTGlzdBIcCglhZGRyZXNzZXMYASADKAlSCWFkZHJlc3Nlcw==');

@$core.Deprecated('Use balanceDescriptor instead')
const Balance$json = {
  '1': 'Balance',
  '2': [
    {'1': 'valueZat', '3': 1, '4': 1, '5': 3, '10': 'valueZat'},
  ],
};

/// Descriptor for `Balance`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List balanceDescriptor = $convert
    .base64Decode('CgdCYWxhbmNlEhoKCHZhbHVlWmF0GAEgASgDUgh2YWx1ZVphdA==');

@$core.Deprecated('Use getMempoolTxRequestDescriptor instead')
const GetMempoolTxRequest$json = {
  '1': 'GetMempoolTxRequest',
  '2': [
    {
      '1': 'exclude_txid_suffixes',
      '3': 1,
      '4': 3,
      '5': 12,
      '10': 'excludeTxidSuffixes'
    },
    {
      '1': 'poolTypes',
      '3': 3,
      '4': 3,
      '5': 14,
      '6': '.cash.z.wallet.sdk.rpc.PoolType',
      '10': 'poolTypes'
    },
  ],
  '9': [
    {'1': 2, '2': 3},
  ],
};

/// Descriptor for `GetMempoolTxRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMempoolTxRequestDescriptor = $convert.base64Decode(
    'ChNHZXRNZW1wb29sVHhSZXF1ZXN0EjIKFWV4Y2x1ZGVfdHhpZF9zdWZmaXhlcxgBIAMoDFITZX'
    'hjbHVkZVR4aWRTdWZmaXhlcxI9Cglwb29sVHlwZXMYAyADKA4yHy5jYXNoLnoud2FsbGV0LnNk'
    'ay5ycGMuUG9vbFR5cGVSCXBvb2xUeXBlc0oECAIQAw==');

@$core.Deprecated('Use treeStateDescriptor instead')
const TreeState$json = {
  '1': 'TreeState',
  '2': [
    {'1': 'network', '3': 1, '4': 1, '5': 9, '10': 'network'},
    {'1': 'height', '3': 2, '4': 1, '5': 4, '10': 'height'},
    {'1': 'hash', '3': 3, '4': 1, '5': 9, '10': 'hash'},
    {'1': 'time', '3': 4, '4': 1, '5': 13, '10': 'time'},
    {'1': 'saplingTree', '3': 5, '4': 1, '5': 9, '10': 'saplingTree'},
    {'1': 'orchardTree', '3': 6, '4': 1, '5': 9, '10': 'orchardTree'},
    {'1': 'ironwoodTree', '3': 7, '4': 1, '5': 9, '10': 'ironwoodTree'},
  ],
};

/// Descriptor for `TreeState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List treeStateDescriptor = $convert.base64Decode(
    'CglUcmVlU3RhdGUSGAoHbmV0d29yaxgBIAEoCVIHbmV0d29yaxIWCgZoZWlnaHQYAiABKARSBm'
    'hlaWdodBISCgRoYXNoGAMgASgJUgRoYXNoEhIKBHRpbWUYBCABKA1SBHRpbWUSIAoLc2FwbGlu'
    'Z1RyZWUYBSABKAlSC3NhcGxpbmdUcmVlEiAKC29yY2hhcmRUcmVlGAYgASgJUgtvcmNoYXJkVH'
    'JlZRIiCgxpcm9ud29vZFRyZWUYByABKAlSDGlyb253b29kVHJlZQ==');

@$core.Deprecated('Use getSubtreeRootsArgDescriptor instead')
const GetSubtreeRootsArg$json = {
  '1': 'GetSubtreeRootsArg',
  '2': [
    {'1': 'startIndex', '3': 1, '4': 1, '5': 13, '10': 'startIndex'},
    {
      '1': 'shieldedProtocol',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.cash.z.wallet.sdk.rpc.ShieldedProtocol',
      '10': 'shieldedProtocol'
    },
    {'1': 'maxEntries', '3': 3, '4': 1, '5': 13, '10': 'maxEntries'},
  ],
};

/// Descriptor for `GetSubtreeRootsArg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSubtreeRootsArgDescriptor = $convert.base64Decode(
    'ChJHZXRTdWJ0cmVlUm9vdHNBcmcSHgoKc3RhcnRJbmRleBgBIAEoDVIKc3RhcnRJbmRleBJTCh'
    'BzaGllbGRlZFByb3RvY29sGAIgASgOMicuY2FzaC56LndhbGxldC5zZGsucnBjLlNoaWVsZGVk'
    'UHJvdG9jb2xSEHNoaWVsZGVkUHJvdG9jb2wSHgoKbWF4RW50cmllcxgDIAEoDVIKbWF4RW50cm'
    'llcw==');

@$core.Deprecated('Use subtreeRootDescriptor instead')
const SubtreeRoot$json = {
  '1': 'SubtreeRoot',
  '2': [
    {'1': 'rootHash', '3': 2, '4': 1, '5': 12, '10': 'rootHash'},
    {
      '1': 'completingBlockHash',
      '3': 3,
      '4': 1,
      '5': 12,
      '10': 'completingBlockHash'
    },
    {
      '1': 'completingBlockHeight',
      '3': 4,
      '4': 1,
      '5': 4,
      '10': 'completingBlockHeight'
    },
  ],
};

/// Descriptor for `SubtreeRoot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List subtreeRootDescriptor = $convert.base64Decode(
    'CgtTdWJ0cmVlUm9vdBIaCghyb290SGFzaBgCIAEoDFIIcm9vdEhhc2gSMAoTY29tcGxldGluZ0'
    'Jsb2NrSGFzaBgDIAEoDFITY29tcGxldGluZ0Jsb2NrSGFzaBI0ChVjb21wbGV0aW5nQmxvY2tI'
    'ZWlnaHQYBCABKARSFWNvbXBsZXRpbmdCbG9ja0hlaWdodA==');

@$core.Deprecated('Use getAddressUtxosArgDescriptor instead')
const GetAddressUtxosArg$json = {
  '1': 'GetAddressUtxosArg',
  '2': [
    {'1': 'addresses', '3': 1, '4': 3, '5': 9, '10': 'addresses'},
    {'1': 'startHeight', '3': 2, '4': 1, '5': 4, '10': 'startHeight'},
    {'1': 'maxEntries', '3': 3, '4': 1, '5': 13, '10': 'maxEntries'},
  ],
};

/// Descriptor for `GetAddressUtxosArg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getAddressUtxosArgDescriptor = $convert.base64Decode(
    'ChJHZXRBZGRyZXNzVXR4b3NBcmcSHAoJYWRkcmVzc2VzGAEgAygJUglhZGRyZXNzZXMSIAoLc3'
    'RhcnRIZWlnaHQYAiABKARSC3N0YXJ0SGVpZ2h0Eh4KCm1heEVudHJpZXMYAyABKA1SCm1heEVu'
    'dHJpZXM=');

@$core.Deprecated('Use getAddressUtxosReplyDescriptor instead')
const GetAddressUtxosReply$json = {
  '1': 'GetAddressUtxosReply',
  '2': [
    {'1': 'address', '3': 6, '4': 1, '5': 9, '10': 'address'},
    {'1': 'txid', '3': 1, '4': 1, '5': 12, '10': 'txid'},
    {'1': 'index', '3': 2, '4': 1, '5': 5, '10': 'index'},
    {'1': 'script', '3': 3, '4': 1, '5': 12, '10': 'script'},
    {'1': 'valueZat', '3': 4, '4': 1, '5': 3, '10': 'valueZat'},
    {'1': 'height', '3': 5, '4': 1, '5': 4, '10': 'height'},
  ],
};

/// Descriptor for `GetAddressUtxosReply`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getAddressUtxosReplyDescriptor = $convert.base64Decode(
    'ChRHZXRBZGRyZXNzVXR4b3NSZXBseRIYCgdhZGRyZXNzGAYgASgJUgdhZGRyZXNzEhIKBHR4aW'
    'QYASABKAxSBHR4aWQSFAoFaW5kZXgYAiABKAVSBWluZGV4EhYKBnNjcmlwdBgDIAEoDFIGc2Ny'
    'aXB0EhoKCHZhbHVlWmF0GAQgASgDUgh2YWx1ZVphdBIWCgZoZWlnaHQYBSABKARSBmhlaWdodA'
    '==');

@$core.Deprecated('Use getAddressUtxosReplyListDescriptor instead')
const GetAddressUtxosReplyList$json = {
  '1': 'GetAddressUtxosReplyList',
  '2': [
    {
      '1': 'addressUtxos',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.GetAddressUtxosReply',
      '10': 'addressUtxos'
    },
  ],
};

/// Descriptor for `GetAddressUtxosReplyList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getAddressUtxosReplyListDescriptor =
    $convert.base64Decode(
        'ChhHZXRBZGRyZXNzVXR4b3NSZXBseUxpc3QSTwoMYWRkcmVzc1V0eG9zGAEgAygLMisuY2FzaC'
        '56LndhbGxldC5zZGsucnBjLkdldEFkZHJlc3NVdHhvc1JlcGx5UgxhZGRyZXNzVXR4b3M=');
