import 'dart:typed_data';

import '../../../rust/api/ledger.dart' as rust_ledger;
import 'ledger_mobile_ble_service.dart';

typedef LedgerDeviceAccountResponseValidator =
    Future<void> Function({
      required List<int> expectedPublicKey,
      required List<int> response,
    });

/// A device reply to Ironwood transaction data, before a signature was requested.
class LedgerIronwoodDataRejected implements Exception {
  const LedgerIronwoodDataRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

/// BLE stops at the first failed APDU. Match that reply to the command actually
/// sent, and require every earlier exchange to be successful transaction data.
bool ledgerRejectedIronwoodData(
  List<rust_ledger.LedgerApduCommand> commands,
  List<Uint8List> responses,
) {
  if (responses.isEmpty || responses.length > commands.length) return false;
  for (var i = 0; i < responses.length; i++) {
    final command = commands[i];
    final response = responses[i];
    if (command.cla != 0xe0 ||
        !const {0x52, 0x53, 0x54, 0x56, 0x58}.contains(command.ins) ||
        response.length < 2) {
      return false;
    }
    final status = response[response.length - 2] << 8 | response.last;
    if (status != 0x9000) {
      return i == responses.length - 1 &&
          command.ins == 0x58 &&
          status == 0x6a80;
    }
  }
  return false;
}

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
