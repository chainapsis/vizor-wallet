import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';

void main() {
  test('findProfilePictureOption resolves legacy knight ids', () {
    final option = findProfilePictureOption('knight-02');

    expect(option, isNotNull);
    expect(option!.id, 'knight');
    expect(option.assetPath, kKnightProfilePictureAsset);
  });

  test('findProfilePictureOption rejects malformed legacy ids', () {
    expect(findProfilePictureOption('knight-'), isNull);
    expect(findProfilePictureOption('knight-2'), isNull);
    expect(findProfilePictureOption('unknown'), isNull);
  });
}
