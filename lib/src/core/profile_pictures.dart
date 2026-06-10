const kDefaultProfilePictureId = 'pfp-01';
const _kProfilePictureAssetRoot = 'assets/profile_pictures';
final _legacyKnightVariantPattern = RegExp(r'^knight-(\d{2})$');
const _legacyKnightVariantMap = {'04': 'pfp-04', '05': 'pfp-05'};
const _legacyProfilePictureIdMap = {
  'knight': 'pfp-01',
  'viking': 'pfp-02',
  'samurai': 'pfp-03',
  'wizard': 'pfp-11',
  'chest': kDefaultProfilePictureId,
  'dragon': kDefaultProfilePictureId,
  'shield-1': kDefaultProfilePictureId,
  'shield-2': kDefaultProfilePictureId,
};

class ProfilePictureOption {
  const ProfilePictureOption({
    required this.id,
    required this.label,
    required this.assetPath,
  });

  final String id;
  final String label;
  final String assetPath;
}

const _kProfilePictureSuffixes = [
  '01',
  '02',
  '03',
  '04',
  '05',
  '06',
  '07',
  '08',
  '09',
  '10',
  '11',
  '12',
  '13',
  '14',
  '15',
];

final kProfilePictureOptions = <ProfilePictureOption>[
  for (final suffix in _kProfilePictureSuffixes)
    ProfilePictureOption(
      id: 'pfp-$suffix',
      label: 'Profile picture ${int.parse(suffix)}',
      assetPath: '$_kProfilePictureAssetRoot/profile_picture_$suffix.png',
    ),
];

ProfilePictureOption? findProfilePictureOption(String id) {
  final normalizedId = _knownProfilePictureId(id);
  if (normalizedId == null) return null;

  for (final option in kProfilePictureOptions) {
    if (option.id == normalizedId) return option;
  }
  return null;
}

ProfilePictureOption resolveProfilePictureOption(String id) {
  return findProfilePictureOption(id) ??
      findProfilePictureOption(kDefaultProfilePictureId)!;
}

String normalizeProfilePictureId(String id) {
  return findProfilePictureOption(id)?.id ?? kDefaultProfilePictureId;
}

bool isKnownProfilePictureId(String id) {
  return findProfilePictureOption(id) != null;
}

String? _knownProfilePictureId(String id) {
  final trimmed = id.trim();
  for (final option in kProfilePictureOptions) {
    if (option.id == trimmed) return option.id;
  }
  final knightVariant = _legacyKnightVariantPattern.firstMatch(trimmed);
  if (knightVariant != null) {
    return _legacyKnightVariantMap[knightVariant.group(1)] ??
        kDefaultProfilePictureId;
  }
  return _legacyProfilePictureIdMap[trimmed];
}
