import 'dart:typed_data';

import '../../../rust/api/ledger.dart' as rust_ledger;
import 'ledger_mobile_ble_service.dart';

typedef LedgerDeviceAccountResponseValidator =
    Future<void> Function({
      required List<int> expectedPublicKey,
      required List<int> response,
    });

/// Both payment and voting signers verify the connected account before the
/// first transaction byte. Keeping the probe separate from the PCZT exchange
/// is essential: checking it after exchanging the whole plan is too late.
Future<List<Uint8List>> exchangeLedgerSigningPlan({
  required LedgerMobileBleService mobile,
  required rust_ledger.LedgerPcztApduPlan plan,
  required void Function() check,
  required void Function(String) progress,
  LedgerDeviceAccountResponseValidator validateDeviceAccount =
      rust_ledger.ledgerValidateDeviceAccountResponse,
}) async {
  check();
  final probeResponses = await mobile.exchangeApdus([
    plan.deviceAccountKeyRequest,
  ]);
  check();
  if (probeResponses.length != 1) {
    throw StateError('Ledger account-key response is missing or unexpected.');
  }
  await validateDeviceAccount(
    expectedPublicKey: plan.expectedDevicePublicKey,
    response: probeResponses.single,
  );
  check();

  if (mobile is LedgerProgressBleService) {
    return (mobile as LedgerProgressBleService).exchangeApdusWithProgress(
      plan.commands,
      progress,
    );
  }
  // Custom/test transports without native events cannot claim review is visible.
  progress('sending');
  final responses = await mobile.exchangeApdus(plan.commands);
  progress('finishing');
  return responses;
}
