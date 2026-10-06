import 'dart:convert';
import 'dart:io';

import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

/// The Activity row and receipt that Vizor's Rust history read produces for
/// the two reported transparent-to-Ironwood shieldings after the library
/// recovers them by private queries only. `private_shielding_tests.rs` writes
/// and checks `private_shielding_activity.json`; chain identifiers are
/// supplied here.
class PrivateShieldingCase {
  const PrivateShieldingCase(this.transaction, this.detail);

  final rust_sync.TransactionInfo transaction;
  final rust_sync.TransactionDetail detail;
}

List<PrivateShieldingCase> loadPrivateShieldingCases({
  required String txidHex,
  required BigInt minedHeight,
  required BigInt blockTime,
}) {
  final cases =
      jsonDecode(
            File(
              'test/fixtures/private_shielding_activity.json',
            ).readAsStringSync(),
          )
          as List<dynamic>;
  return [
    for (final entry in cases.cast<Map<String, dynamic>>())
      _case(entry, txidHex, minedHeight, blockTime),
  ];
}

PrivateShieldingCase _case(
  Map<String, dynamic> entry,
  String txidHex,
  BigInt minedHeight,
  BigInt blockTime,
) {
  final tx = entry['transaction'] as Map<String, dynamic>;
  final detail = entry['detail'] as Map<String, dynamic>;
  return PrivateShieldingCase(
    rust_sync.TransactionInfo(
      txidHex: txidHex,
      minedHeight: minedHeight,
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
      createdTime: blockTime,
    ),
    rust_sync.TransactionDetail(
      txidHex: txidHex,
      txKind: detail['txKind'] as String,
      memo: detail['memo'] as String?,
      detailsComplete: detail['detailsComplete'] as bool,
      provisional: detail['provisional'] as bool,
      outputs: [
        for (final output
            in (detail['outputs'] as List<dynamic>)
                .cast<Map<String, dynamic>>())
          rust_sync.TransactionDetailOutput(
            amountZatoshi: BigInt.from(output['amountZatoshi'] as int),
            pool: output['pool'] as String,
            usesOrchardReceiver: false,
          ),
      ],
    ),
  );
}
