@Tags(['figma-capture'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'font_input_capture_support.dart';

void main() {
  const output = String.fromEnvironment('FONT_INPUT_CAPTURE_DIR');
  if (output.isNotEmpty) runFontInputCaptures(mobile: false, output: output);
}
