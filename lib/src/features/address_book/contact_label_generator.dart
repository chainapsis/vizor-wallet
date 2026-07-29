import 'dart:math';

import '../../core/profile_pictures.dart';

/// Persona pool for auto-named contacts (e.g. a swap address saved through
/// 'Remember this address'). Names follow the app's medieval-keep identity —
/// the cast that would live around the Vizor castle.
const kGeneratedContactPersonas = <String>[
  'Squire',
  'Knight',
  'Warden',
  'Sentinel',
  'Herald',
  'Falconer',
  'Templar',
  'Paladin',
  'Archer',
  'Marshal',
  'Keeper',
  'Ranger',
  'Scribe',
  'Bard',
  'Alchemist',
  'Castellan',
];

/// Picks a persona label that does not collide with [existingLabels]
/// (case-insensitively). Collisions get a numeric suffix ('Warden 2',
/// 'Warden 3', ...); callers that persist labels still enforce the address-book
/// 20-character limit.
String generateContactLabel({
  required Iterable<String> existingLabels,
  Random? random,
}) {
  final rng = random ?? Random();
  final taken = {
    for (final label in existingLabels) label.trim().toLowerCase(),
  };
  final persona =
      kGeneratedContactPersonas[rng.nextInt(kGeneratedContactPersonas.length)];
  if (!taken.contains(persona.toLowerCase())) return persona;
  for (var n = 2; ; n++) {
    final candidate = '$persona $n';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}

/// Picks a random avatar for a newly created contact.
String randomContactProfilePictureId({Random? random}) {
  final rng = random ?? Random();
  return kProfilePictureOptions[rng.nextInt(kProfilePictureOptions.length)].id;
}
