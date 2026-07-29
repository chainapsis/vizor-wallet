import 'dart:math';

import '../../../core/account_name_policy.dart';
import '../../../core/profile_pictures.dart';

const kAccountPersonaAdjectives = <String>[
  'Windborne',
  'Steadfast',
  'Dutiful',
  'Valiant',
  'Clever',
  'Radiant',
  'Resolute',
  'Gentle',
  'Stalwart',
  'Vigilant',
  'Dawnlit',
  'Moonlit',
  'Trailwise',
  'Silver',
  'Emerald',
  'Amber',
  'Ivory',
  'Mistbound',
  'Loyal',
  'Kindred',
];

const kAccountPersonaArchetypes = <String>[
  'Protector',
  'Wardbearer',
  'Defender',
  'Banneret',
  'Wayfinder',
  'Pathfinder',
  'Steward',
  'Herald',
  'Falconer',
  'Castellan',
  'Observer',
  'Envoy',
  'Voyager',
  'Scholar',
  'Artificer',
  'Caretaker',
  'Captain',
  'Smith',
  'Trailguard',
  'Pioneer',
];

class AccountPersonaSuggestion {
  const AccountPersonaSuggestion({
    required this.name,
    required this.profilePictureId,
  });

  final String name;
  final String profilePictureId;
}

AccountPersonaSuggestion generateAccountPersona({Random? random}) {
  final rng = random ?? Random();
  final adjective =
      kAccountPersonaAdjectives[rng.nextInt(kAccountPersonaAdjectives.length)];
  final archetype =
      kAccountPersonaArchetypes[rng.nextInt(kAccountPersonaArchetypes.length)];
  final name = '$adjective $archetype';
  validateAccountName(name);

  final profilePictureId =
      kProfilePictureOptions[rng.nextInt(kProfilePictureOptions.length)].id;
  return AccountPersonaSuggestion(
    name: name,
    profilePictureId: profilePictureId,
  );
}
