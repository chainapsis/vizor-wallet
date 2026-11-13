import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_destinations.dart';

void main() {
  final icons = mobileDestinations.map((tab) => tab.iconName).toSet();
  const catalog = 'ios/Runner/Assets.xcassets';

  test('native catalog covers exactly the mobile destination icons', () {
    final sets = Directory(catalog)
        .listSync()
        .whereType<Directory>()
        .map(
          (directory) =>
              directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        )
        .where((name) => name.startsWith('VizorTab_'))
        .toSet();
    expect(sets, {for (final icon in icons) 'VizorTab_$icon.imageset'});
  });

  for (final icon in icons) {
    test(
      'native $icon SVG is an exact template copy of its Flutter source',
      () {
        final set = '$catalog/VizorTab_$icon.imageset';
        final source = File('assets/icons/$icon.svg').readAsBytesSync();
        expect(File('$set/$icon.svg').readAsBytesSync(), orderedEquals(source));
        expect(jsonDecode(File('$set/Contents.json').readAsStringSync()), {
          'images': [
            {'filename': '$icon.svg', 'idiom': 'universal'},
          ],
          'info': {'author': 'xcode', 'version': 1},
          'properties': {
            'template-rendering-intent': 'template',
            'preserves-vector-representation': true,
          },
        });
      },
    );
  }
}
