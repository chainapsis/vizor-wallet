import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Tor data directory name is declared twice: `getTorDataDirectoryPath`
/// appends it in Dart, and Android's data-extraction rules exclude the same
/// path from backup and device-to-device transfer. The two are hand-typed
/// literals, and a divergence fails quietly: arti re-downloads its directory
/// cache under the new name while the old exclusion guards an empty path, so
/// the wallet's guard choice rides along to a transferred device.
void main() {
  test('the Android backup exclusion names the Tor directory Dart uses', () {
    final dart = File(
      'lib/src/core/storage/wallet_paths.dart',
    ).readAsStringSync();
    expect(
      dart,
      contains(r"${Platform.pathSeparator}tor"),
      reason: 'getTorDataDirectoryPath no longer appends the tor directory; '
          'update android/app/src/main/res/xml/data_extraction_rules.xml '
          'with it',
    );

    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(rules, contains('path="tor"'));
  });
}
