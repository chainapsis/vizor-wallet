import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/account_name_policy.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/address_book/contact_label_generator.dart';

void main() {
  test('picks labels from the persona pool', () {
    for (var seed = 0; seed < 20; seed++) {
      final label = generateContactLabel(
        existingLabels: const [],
        random: Random(seed),
      );
      expect(kGeneratedContactPersonas, contains(label));
    }
  });

  test('suffixes collisions case-insensitively', () {
    final label = generateContactLabel(
      existingLabels: [
        for (final persona in kGeneratedContactPersonas) persona.toLowerCase(),
      ],
      random: Random(1),
    );
    expect(kGeneratedContactPersonas.any((p) => label == '$p 2'), isTrue);

    final third = generateContactLabel(
      existingLabels: [
        for (final persona in kGeneratedContactPersonas) persona,
        for (final persona in kGeneratedContactPersonas) '$persona 2',
      ],
      random: Random(1),
    );
    expect(kGeneratedContactPersonas.any((p) => third == '$p 3'), isTrue);
  });

  test('every persona stays within the 20-character label limit', () {
    for (final persona in kGeneratedContactPersonas) {
      // Leave room for a collision suffix up to ' 99'.
      expect(accountNameCharacterLength('$persona 99'), lessThanOrEqualTo(20));
    }
  });

  test('random avatar ids resolve to known profile pictures', () {
    for (var seed = 0; seed < 20; seed++) {
      final id = randomContactProfilePictureId(random: Random(seed));
      expect(kProfilePictureOptions.map((o) => o.id), contains(id));
    }
  });
}
