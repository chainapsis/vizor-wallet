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

import 'package:protobuf/protobuf.dart' as $pb;

/// An identifier for a Zcash value pool.
class PoolType extends $pb.ProtobufEnum {
  static const PoolType POOL_TYPE_INVALID =
      PoolType._(0, _omitEnumNames ? '' : 'POOL_TYPE_INVALID');
  static const PoolType TRANSPARENT =
      PoolType._(1, _omitEnumNames ? '' : 'TRANSPARENT');
  static const PoolType SAPLING =
      PoolType._(2, _omitEnumNames ? '' : 'SAPLING');
  static const PoolType ORCHARD =
      PoolType._(3, _omitEnumNames ? '' : 'ORCHARD');
  static const PoolType IRONWOOD =
      PoolType._(4, _omitEnumNames ? '' : 'IRONWOOD');

  static const $core.List<PoolType> values = <PoolType>[
    POOL_TYPE_INVALID,
    TRANSPARENT,
    SAPLING,
    ORCHARD,
    IRONWOOD,
  ];

  static final $core.List<PoolType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static PoolType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PoolType._(super.value, super.name);
}

class ShieldedProtocol extends $pb.ProtobufEnum {
  static const ShieldedProtocol sapling =
      ShieldedProtocol._(0, _omitEnumNames ? '' : 'sapling');
  static const ShieldedProtocol orchard =
      ShieldedProtocol._(1, _omitEnumNames ? '' : 'orchard');
  static const ShieldedProtocol ironwood =
      ShieldedProtocol._(2, _omitEnumNames ? '' : 'ironwood');

  static const $core.List<ShieldedProtocol> values = <ShieldedProtocol>[
    sapling,
    orchard,
    ironwood,
  ];

  static final $core.List<ShieldedProtocol?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ShieldedProtocol? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ShieldedProtocol._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
