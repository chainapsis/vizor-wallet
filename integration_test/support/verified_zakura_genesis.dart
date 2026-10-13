import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;

/// A snapshot of the original host's node-verified genesis, not cleanup authority.
final class VerifiedZakuraGenesis {
  const VerifiedZakuraGenesis._(
    this.hash,
    this.time,
    this.fixtureRunId,
    this.upstreamPort,
  );

  final String hash;
  final int time;
  final String fixtureRunId;
  final int upstreamPort;
  static const maxProofBytes = 64 * 1024;
  static const emptyTreeCodec =
      'zakura-primitives-2.0.0:legacy-commitment-tree-none-none-empty-vector';

  static Future<VerifiedZakuraGenesis> read(
    String path, {
    required String expectedSha256,
    required String fixtureRunId,
    required int upstreamPort,
  }) async {
    final file = File(path);
    final details = await file.stat();
    final parent = await file.parent.stat();
    if (file.absolute.path != path ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != path ||
        details.size > maxProofBytes ||
        details.mode & 0x1ff != 0x100 ||
        parent.mode & 0x1ff != 0x1c0) {
      throw const FormatException(
        'genesis proof must be private and read-only',
      );
    }
    final handle = await file.open(mode: FileMode.read);
    final List<int> bytes;
    try {
      bytes = await handle.read(maxProofBytes + 1);
    } finally {
      await handle.close();
    }
    if (bytes.length > maxProofBytes ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256) ||
        sha256.convert(bytes).toString() != expectedSha256) {
      throw const FormatException('genesis proof digest or size is invalid');
    }
    return _parse(
      jsonDecode(utf8.decode(bytes)),
      fixtureRunId: fixtureRunId,
      upstreamPort: upstreamPort,
    );
  }

  static VerifiedZakuraGenesis _parse(
    Object? value, {
    required String fixtureRunId,
    required int upstreamPort,
  }) {
    Never invalid() =>
        throw const FormatException('invalid node-verified genesis proof');
    Map<String, dynamic> object(Object? value) =>
        value is Map && value.keys.every((key) => key is String)
        ? Map<String, dynamic>.from(value)
        : invalid();
    final proof = object(value);
    final identity = object(proof['identity']);
    final block = object(proof['genesis_block']);
    final tree = object(proof['genesis_node_tree']);
    final state = object(proof['tree_state']);
    final hash = state['hash'];
    final time = state['time'];
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(fixtureRunId) ||
        proof['schema_version'] is! int ||
        proof['schema_version'] != 1 ||
        proof['fixture_run_id'] != fixtureRunId ||
        identity['run_id'] != fixtureRunId ||
        proof['upstream_port'] is! int ||
        proof['upstream_port'] != upstreamPort ||
        upstreamPort < 1 ||
        upstreamPort > 65535 ||
        proof['empty_tree_codec'] != emptyTreeCodec ||
        proof['wallet_or_catalog_pass'] != false ||
        hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        hash == '0' * 64 ||
        time is! int ||
        time <= 0 ||
        time > 0xffffffff ||
        state['network'] != 'regtest' ||
        state['height'] != '0' ||
        block['hash'] != hash ||
        tree['hash'] != hash ||
        block['height'] is! int ||
        block['height'] != 0 ||
        tree['height'] is! int ||
        tree['height'] != 0 ||
        block['time'] is! int ||
        tree['time'] is! int ||
        block['time'] != time ||
        tree['time'] != time) {
      invalid();
    }
    final transactions = block['tx'];
    if (block['nTx'] is! int ||
        block['nTx'] != 1 ||
        transactions is! List ||
        transactions.length != 1) {
      invalid();
    }
    final transaction = object(transactions.single);
    final inputs = transaction['vin'];
    if (transaction['version'] is! int ||
        transaction['version'] != 1 ||
        transaction['overwintered'] != false ||
        transaction['blockhash'] != hash ||
        transaction['height'] is! int ||
        transaction['height'] != 0 ||
        inputs is! List ||
        inputs.length != 1 ||
        object(inputs.single)['coinbase'] is! String ||
        (object(inputs.single)['coinbase'] as String).isEmpty) {
      invalid();
    }
    for (final field in ['vShieldedSpend', 'vShieldedOutput', 'vjoinsplit']) {
      if (transaction[field] is! List ||
          (transaction[field] as List).isNotEmpty) {
        invalid();
      }
    }
    for (final pool in ['orchard', 'ironwood']) {
      if (pool == 'ironwood' && !transaction.containsKey(pool)) continue;
      final actions = object(transaction[pool])['actions'];
      if (actions is! List || actions.isNotEmpty) invalid();
    }
    final pools = block['valuePools'];
    if (pools is! List) invalid();
    for (final pool in ['sapling', 'orchard', 'ironwood']) {
      final nodePool = object(tree[pool]);
      if (nodePool.length != 1 || object(nodePool['commitments']).isNotEmpty) {
        invalid();
      }
      final matches = pools
          .where((value) => object(value)['id'] == pool)
          .toList();
      if (matches.length != 1) invalid();
      final entry = object(matches.single);
      for (final field in ['chainValueZat', 'valueDeltaZat']) {
        if (entry[field] is! int || entry[field] != 0) invalid();
      }
      if (state['${pool}Tree'] != '000000') invalid();
    }
    return VerifiedZakuraGenesis._(hash, time, fixtureRunId, upstreamPort);
  }

  service.TreeState treeState() => service.TreeState(
    network: 'regtest',
    height: Int64.ZERO,
    hash: hash,
    time: time,
    saplingTree: '000000',
    orchardTree: '000000',
    ironwoodTree: '000000',
  );
}
