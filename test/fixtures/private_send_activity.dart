import 'dart:convert';
import 'dart:io';

import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

/// The Activity rows Vizor's Rust history read produces for the reported
/// shielded send with a transparent output (250,000 zatoshis sent, 15,000
/// fee), restored publicly and privately. `private_send_activity_tests.rs`
/// writes and checks `private_send_activity.json`; chain identifiers are
/// supplied here.
class PrivateSendActivity {
  const PrivateSendActivity(
    this.public,
    this.private,
    this.privateWithoutTransparentRows,
  );

  /// The public restore, which stores the full transaction.
  final List<rust_sync.TransactionInfo> public;

  /// The private restore that also recovered the account's own transparent
  /// output.
  final List<rust_sync.TransactionInfo> private;

  /// The private restore with no transparent rows or transparent metadata.
  final List<rust_sync.TransactionInfo> privateWithoutTransparentRows;
}

PrivateSendActivity loadPrivateSendActivity() {
  final fixture =
      jsonDecode(
            File('test/fixtures/private_send_activity.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  List<rust_sync.TransactionInfo> rows(String key) => [
    for (final row
        in (fixture[key] as List<dynamic>).cast<Map<String, dynamic>>())
      _transaction(row),
  ];
  return PrivateSendActivity(
    rows('public'),
    rows('private'),
    rows('privateWithoutTransparentRows'),
  );
}

rust_sync.TransactionInfo _transaction(Map<String, dynamic> tx) {
  final blockTime = BigInt.from(1750000000);
  return rust_sync.TransactionInfo(
    txidHex: 'fixture',
    minedHeight: BigInt.from(121),
    expiredUnmined: tx['expiredUnmined'] as bool,
    accountBalanceDelta: tx['accountBalanceDelta'] as int,
    fee: BigInt.from(tx['fee'] as int),
    feeState: switch (tx['feeState'] as String) {
      'Known' => rust_sync.TransactionFeeState.known,
      'Unknown' => rust_sync.TransactionFeeState.unknown,
      'NotApplicable' => rust_sync.TransactionFeeState.notApplicable,
      final other => throw ArgumentError('fee state $other'),
    },
    detailsComplete: tx['detailsComplete'] as bool,
    provisional: tx['provisional'] as bool,
    amountIncludesFee: tx['amountIncludesFee'] as bool,
    blockTime: blockTime,
    isTransparent: tx['isTransparent'] as bool,
    txKind: tx['txKind'] as String,
    displayAmount: BigInt.from(tx['displayAmount'] as int),
    displayPool: tx['displayPool'] as String,
    activityPool: tx['activityPool'] as String?,
    createdTime: blockTime,
  );
}
