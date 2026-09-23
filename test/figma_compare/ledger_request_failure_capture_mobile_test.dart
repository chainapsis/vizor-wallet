@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'ledger_pairing_capture_support.dart';

void main() {
  const output = String.fromEnvironment('LEDGER_CAPTURE_DIR');
  if (output.isEmpty) return;
  runLedgerRequestFailureCaptures(mobile: true, output: output);
}
