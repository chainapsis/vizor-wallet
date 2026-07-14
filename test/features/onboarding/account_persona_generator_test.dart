import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/account_name_policy.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/onboarding/create/account_persona_generator.dart';

void main() {
  test(
    'uses the injected Random for the name and existing profile catalog',
    () {
      final suggestion = generateAccountPersona(
        random: _SequenceRandom([0, 1, 2]),
      );

      expect(suggestion.name, 'Veiled Wardbearer');
      expect(suggestion.profilePictureId, 'pfp-03');
    },
  );

  test('uses a curated vocabulary distinct from the direction examples', () {
    const exampleAdjectives = {
      'Shielded',
      'Quiet',
      'Hidden',
      'Golden',
      'Noble',
      'Iron',
      'Silent',
      'Bright',
      'Trusted',
      'Verdant',
    };
    const exampleArchetypes = {
      'Knight',
      'Viking',
      'Samurai',
      'Ronin',
      'Ninja',
      'Ranger',
      'Archer',
      'Sentinel',
      'Warden',
      'Guardian',
      'Paladin',
      'Squire',
      'Marshal',
      'Scout',
      'Champion',
      'Duelist',
      'Rogue',
      'Mage',
      'Seer',
      'Alchemist',
    };

    expect(
      kAccountPersonaAdjectives.toSet().intersection(exampleAdjectives),
      isEmpty,
    );
    expect(
      kAccountPersonaArchetypes.toSet().intersection(exampleArchetypes),
      isEmpty,
    );
  });

  test('the same seeded Random produces the same suggestion', () {
    final first = generateAccountPersona(random: Random(1234));
    final second = generateAccountPersona(random: Random(1234));

    expect(second.name, first.name);
    expect(second.profilePictureId, first.profilePictureId);
  });

  test('every generated name follows the account-name policy', () {
    const avoidedTerms = {
      'vault',
      'keep',
      'treasury',
      'ledger',
      'chest',
      'assassin',
      'raider',
      'conqueror',
      'mercenary',
      'anonymous',
      'dark',
      'secret cash',
    };

    for (final adjective in kAccountPersonaAdjectives) {
      for (final archetype in kAccountPersonaArchetypes) {
        final name = '$adjective $archetype';
        expect(isAccountNameLengthValid(name), isTrue, reason: name);
        expect(
          avoidedTerms.any(name.toLowerCase().contains),
          isFalse,
          reason: name,
        );
      }
    }
  });

  test('every generated profile id belongs to the existing catalog', () {
    for (var seed = 0; seed < 30; seed++) {
      final suggestion = generateAccountPersona(random: Random(seed));
      expect(
        kProfilePictureOptions.map((option) => option.id),
        contains(suggestion.profilePictureId),
      );
    }
  });
}

class _SequenceRandom implements Random {
  _SequenceRandom(this._values);

  final List<int> _values;
  var _index = 0;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 26) / (1 << 26);

  @override
  int nextInt(int max) {
    final value = _values[_index++ % _values.length];
    return value % max;
  }
}
