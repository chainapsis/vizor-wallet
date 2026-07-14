// This is a generated file - do not edit.
//
// Generated from compact_formats.proto.

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

@$core.Deprecated('Use chainMetadataDescriptor instead')
const ChainMetadata$json = {
  '1': 'ChainMetadata',
  '2': [
    {
      '1': 'saplingCommitmentTreeSize',
      '3': 1,
      '4': 1,
      '5': 13,
      '10': 'saplingCommitmentTreeSize'
    },
    {
      '1': 'orchardCommitmentTreeSize',
      '3': 2,
      '4': 1,
      '5': 13,
      '10': 'orchardCommitmentTreeSize'
    },
    {
      '1': 'ironwoodCommitmentTreeSize',
      '3': 3,
      '4': 1,
      '5': 13,
      '10': 'ironwoodCommitmentTreeSize'
    },
  ],
};

/// Descriptor for `ChainMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chainMetadataDescriptor = $convert.base64Decode(
    'Cg1DaGFpbk1ldGFkYXRhEjwKGXNhcGxpbmdDb21taXRtZW50VHJlZVNpemUYASABKA1SGXNhcG'
    'xpbmdDb21taXRtZW50VHJlZVNpemUSPAoZb3JjaGFyZENvbW1pdG1lbnRUcmVlU2l6ZRgCIAEo'
    'DVIZb3JjaGFyZENvbW1pdG1lbnRUcmVlU2l6ZRI+Chppcm9ud29vZENvbW1pdG1lbnRUcmVlU2'
    'l6ZRgDIAEoDVIaaXJvbndvb2RDb21taXRtZW50VHJlZVNpemU=');

@$core.Deprecated('Use compactBlockDescriptor instead')
const CompactBlock$json = {
  '1': 'CompactBlock',
  '2': [
    {'1': 'protoVersion', '3': 1, '4': 1, '5': 13, '10': 'protoVersion'},
    {'1': 'height', '3': 2, '4': 1, '5': 4, '10': 'height'},
    {'1': 'hash', '3': 3, '4': 1, '5': 12, '10': 'hash'},
    {'1': 'prevHash', '3': 4, '4': 1, '5': 12, '10': 'prevHash'},
    {'1': 'time', '3': 5, '4': 1, '5': 13, '10': 'time'},
    {'1': 'header', '3': 6, '4': 1, '5': 12, '10': 'header'},
    {
      '1': 'vtx',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.CompactTx',
      '10': 'vtx'
    },
    {
      '1': 'chainMetadata',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.ChainMetadata',
      '10': 'chainMetadata'
    },
  ],
};

/// Descriptor for `CompactBlock`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compactBlockDescriptor = $convert.base64Decode(
    'CgxDb21wYWN0QmxvY2sSIgoMcHJvdG9WZXJzaW9uGAEgASgNUgxwcm90b1ZlcnNpb24SFgoGaG'
    'VpZ2h0GAIgASgEUgZoZWlnaHQSEgoEaGFzaBgDIAEoDFIEaGFzaBIaCghwcmV2SGFzaBgEIAEo'
    'DFIIcHJldkhhc2gSEgoEdGltZRgFIAEoDVIEdGltZRIWCgZoZWFkZXIYBiABKAxSBmhlYWRlch'
    'IyCgN2dHgYByADKAsyIC5jYXNoLnoud2FsbGV0LnNkay5ycGMuQ29tcGFjdFR4UgN2dHgSSgoN'
    'Y2hhaW5NZXRhZGF0YRgIIAEoCzIkLmNhc2guei53YWxsZXQuc2RrLnJwYy5DaGFpbk1ldGFkYX'
    'RhUg1jaGFpbk1ldGFkYXRh');

@$core.Deprecated('Use compactTxDescriptor instead')
const CompactTx$json = {
  '1': 'CompactTx',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 4, '10': 'index'},
    {'1': 'txid', '3': 2, '4': 1, '5': 12, '10': 'txid'},
    {'1': 'fee', '3': 3, '4': 1, '5': 13, '10': 'fee'},
    {
      '1': 'spends',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.CompactSaplingSpend',
      '10': 'spends'
    },
    {
      '1': 'outputs',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.CompactSaplingOutput',
      '10': 'outputs'
    },
    {
      '1': 'actions',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.CompactOrchardAction',
      '10': 'actions'
    },
    {
      '1': 'vin',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.CompactTxIn',
      '10': 'vin'
    },
    {
      '1': 'vout',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.TxOut',
      '10': 'vout'
    },
    {
      '1': 'ironwoodActions',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.cash.z.wallet.sdk.rpc.CompactOrchardAction',
      '10': 'ironwoodActions'
    },
  ],
};

/// Descriptor for `CompactTx`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compactTxDescriptor = $convert.base64Decode(
    'CglDb21wYWN0VHgSFAoFaW5kZXgYASABKARSBWluZGV4EhIKBHR4aWQYAiABKAxSBHR4aWQSEA'
    'oDZmVlGAMgASgNUgNmZWUSQgoGc3BlbmRzGAQgAygLMiouY2FzaC56LndhbGxldC5zZGsucnBj'
    'LkNvbXBhY3RTYXBsaW5nU3BlbmRSBnNwZW5kcxJFCgdvdXRwdXRzGAUgAygLMisuY2FzaC56Ln'
    'dhbGxldC5zZGsucnBjLkNvbXBhY3RTYXBsaW5nT3V0cHV0UgdvdXRwdXRzEkUKB2FjdGlvbnMY'
    'BiADKAsyKy5jYXNoLnoud2FsbGV0LnNkay5ycGMuQ29tcGFjdE9yY2hhcmRBY3Rpb25SB2FjdG'
    'lvbnMSNAoDdmluGAcgAygLMiIuY2FzaC56LndhbGxldC5zZGsucnBjLkNvbXBhY3RUeEluUgN2'
    'aW4SMAoEdm91dBgIIAMoCzIcLmNhc2guei53YWxsZXQuc2RrLnJwYy5UeE91dFIEdm91dBJVCg'
    '9pcm9ud29vZEFjdGlvbnMYCSADKAsyKy5jYXNoLnoud2FsbGV0LnNkay5ycGMuQ29tcGFjdE9y'
    'Y2hhcmRBY3Rpb25SD2lyb253b29kQWN0aW9ucw==');

@$core.Deprecated('Use compactTxInDescriptor instead')
const CompactTxIn$json = {
  '1': 'CompactTxIn',
  '2': [
    {'1': 'prevoutTxid', '3': 1, '4': 1, '5': 12, '10': 'prevoutTxid'},
    {'1': 'prevoutIndex', '3': 2, '4': 1, '5': 13, '10': 'prevoutIndex'},
  ],
};

/// Descriptor for `CompactTxIn`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compactTxInDescriptor = $convert.base64Decode(
    'CgtDb21wYWN0VHhJbhIgCgtwcmV2b3V0VHhpZBgBIAEoDFILcHJldm91dFR4aWQSIgoMcHJldm'
    '91dEluZGV4GAIgASgNUgxwcmV2b3V0SW5kZXg=');

@$core.Deprecated('Use txOutDescriptor instead')
const TxOut$json = {
  '1': 'TxOut',
  '2': [
    {'1': 'value', '3': 1, '4': 1, '5': 4, '10': 'value'},
    {'1': 'scriptPubKey', '3': 2, '4': 1, '5': 12, '10': 'scriptPubKey'},
  ],
};

/// Descriptor for `TxOut`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List txOutDescriptor = $convert.base64Decode(
    'CgVUeE91dBIUCgV2YWx1ZRgBIAEoBFIFdmFsdWUSIgoMc2NyaXB0UHViS2V5GAIgASgMUgxzY3'
    'JpcHRQdWJLZXk=');

@$core.Deprecated('Use compactSaplingSpendDescriptor instead')
const CompactSaplingSpend$json = {
  '1': 'CompactSaplingSpend',
  '2': [
    {'1': 'nf', '3': 1, '4': 1, '5': 12, '10': 'nf'},
  ],
};

/// Descriptor for `CompactSaplingSpend`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compactSaplingSpendDescriptor = $convert
    .base64Decode('ChNDb21wYWN0U2FwbGluZ1NwZW5kEg4KAm5mGAEgASgMUgJuZg==');

@$core.Deprecated('Use compactSaplingOutputDescriptor instead')
const CompactSaplingOutput$json = {
  '1': 'CompactSaplingOutput',
  '2': [
    {'1': 'cmu', '3': 1, '4': 1, '5': 12, '10': 'cmu'},
    {'1': 'ephemeralKey', '3': 2, '4': 1, '5': 12, '10': 'ephemeralKey'},
    {'1': 'ciphertext', '3': 3, '4': 1, '5': 12, '10': 'ciphertext'},
  ],
};

/// Descriptor for `CompactSaplingOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compactSaplingOutputDescriptor = $convert.base64Decode(
    'ChRDb21wYWN0U2FwbGluZ091dHB1dBIQCgNjbXUYASABKAxSA2NtdRIiCgxlcGhlbWVyYWxLZX'
    'kYAiABKAxSDGVwaGVtZXJhbEtleRIeCgpjaXBoZXJ0ZXh0GAMgASgMUgpjaXBoZXJ0ZXh0');

@$core.Deprecated('Use compactOrchardActionDescriptor instead')
const CompactOrchardAction$json = {
  '1': 'CompactOrchardAction',
  '2': [
    {'1': 'nullifier', '3': 1, '4': 1, '5': 12, '10': 'nullifier'},
    {'1': 'cmx', '3': 2, '4': 1, '5': 12, '10': 'cmx'},
    {'1': 'ephemeralKey', '3': 3, '4': 1, '5': 12, '10': 'ephemeralKey'},
    {'1': 'ciphertext', '3': 4, '4': 1, '5': 12, '10': 'ciphertext'},
  ],
};

/// Descriptor for `CompactOrchardAction`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compactOrchardActionDescriptor = $convert.base64Decode(
    'ChRDb21wYWN0T3JjaGFyZEFjdGlvbhIcCgludWxsaWZpZXIYASABKAxSCW51bGxpZmllchIQCg'
    'NjbXgYAiABKAxSA2NteBIiCgxlcGhlbWVyYWxLZXkYAyABKAxSDGVwaGVtZXJhbEtleRIeCgpj'
    'aXBoZXJ0ZXh0GAQgASgMUgpjaXBoZXJ0ZXh0');
