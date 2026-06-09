import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';

void main() {
  test('profile picture options use numbered ids in display order', () {
    expect(kProfilePictureOptions, hasLength(15));
    expect(kProfilePictureOptions.map((option) => option.id), [
      'pfp-01',
      'pfp-02',
      'pfp-03',
      'pfp-04',
      'pfp-05',
      'pfp-06',
      'pfp-07',
      'pfp-08',
      'pfp-09',
      'pfp-10',
      'pfp-11',
      'pfp-12',
      'pfp-13',
      'pfp-14',
      'pfp-15',
    ]);
    expect(kProfilePictureOptions.first.label, 'Profile picture 1');
    expect(
      kProfilePictureOptions.first.assetPath,
      'assets/profile_pictures/profile_picture_01.png',
    );
  });

  test('findProfilePictureOption resolves numbered ids only', () {
    final option = findProfilePictureOption('pfp-02');

    expect(option, isNotNull);
    expect(option!.id, 'pfp-02');
    expect(option.assetPath, 'assets/profile_pictures/profile_picture_02.png');
  });

  test('findProfilePictureOption rejects old semantic and malformed ids', () {
    expect(findProfilePictureOption('knight'), isNull);
    expect(findProfilePictureOption('samurai'), isNull);
    expect(findProfilePictureOption('knight-'), isNull);
    expect(findProfilePictureOption('knight-2'), isNull);
    expect(findProfilePictureOption('pfp-2'), isNull);
    expect(findProfilePictureOption('unknown'), isNull);
  });
}
