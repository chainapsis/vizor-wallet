import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Dart signing flows do not derive raw seed bytes', () {
    final productionFiles = Directory('lib/src/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in productionFiles) {
      final content = file.readAsStringSync();
      if (content.contains('deriveSeed(')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
