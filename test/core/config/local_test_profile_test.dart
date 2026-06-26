import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/local_test_profile.dart';

void main() {
  test('normalizes local test profile names in non-release builds', () {
    expect(
      normalizeZcashLocalTestProfile(' Alice-1 ', releaseMode: false),
      'alice-1',
    );
  });

  test('ignores local test profile names in release builds', () {
    expect(normalizeZcashLocalTestProfile('alice', releaseMode: true), isNull);
  });

  test('rejects unsafe local test profile names', () {
    expect(
      () => normalizeZcashLocalTestProfile('../alice', releaseMode: false),
      throwsStateError,
    );
  });
}
