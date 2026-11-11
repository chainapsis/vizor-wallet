@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'language_capture_support.dart';

void main() {
  const output = String.fromEnvironment('LANGUAGE_CAPTURE_DIR');
  if (output.isEmpty) return;
  runLanguageCaptures(mobile: true, output: output);
}
