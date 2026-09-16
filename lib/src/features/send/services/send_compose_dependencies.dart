import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/sync.dart' as rust_sync;
import '../../ledger/ledger_error_messages.dart';

// Scopeable compose dependencies. Production retains the Rust implementations;
// previews can use the real screen without initializing a wallet or Rust.
final sendAddressValidatorProvider = Provider(
  (ref) => rust_sync.validateAddress,
);
final sendFeeEstimatorProvider = Provider((ref) => rust_sync.estimateFee);
final sendMaxEstimatorProvider = Provider((ref) => rust_sync.estimateSendMax);

typedef SendFeeEstimator =
    Future<BigInt> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
      required String toAddress,
      required BigInt amountZatoshi,
      String? memo,
    });
typedef SendMaxEstimator =
    Future<rust_sync.SendMaxEstimateResult> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
      required String toAddress,
      String? memo,
    });
typedef SendAmountQuote = ({BigInt fee, BigInt? suggestedAmount});

/// Only a confirmed Ledger capacity failure can suggest changing an amount.
/// Both calls are read-only; Review creates and locks the actual proposal.
Future<SendAmountQuote> estimateSendAmountQuote({
  required SendFeeEstimator estimateFee,
  required SendMaxEstimator estimateMax,
  required bool isLedger,
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  required BigInt amountZatoshi,
  String? memo,
}) async {
  try {
    final fee = await estimateFee(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
      toAddress: toAddress,
      amountZatoshi: amountZatoshi,
      memo: memo,
    );
    return (fee: fee, suggestedAmount: null);
  } catch (error) {
    if (!isLedger || !ledgerRequestExceedsCapacity(error)) rethrow;
    final max = await estimateMax(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
      toAddress: toAddress,
      memo: memo,
    );
    if (max.amountZatoshi <= BigInt.zero ||
        max.amountZatoshi >= amountZatoshi ||
        max.needsSaplingParams) {
      throw StateError(
        'Ledger amount estimate changed. Try reviewing the amount again.',
      );
    }
    return (fee: max.feeZatoshi, suggestedAmount: max.amountZatoshi);
  }
}
