const kDefaultProfilePictureId = 'knight';
const kKnightProfilePictureAsset =
    'assets/profile_pictures/profile_picture_knight.png';
const _kProfilePictureAssetRoot = 'assets/profile_pictures';

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

final _legacyKnightIdPattern = RegExp(r'^knight-\d{2}$');

const kProfilePictureOptions = <ProfilePictureOption>[
  ProfilePictureOption(
    id: 'knight',
    label: 'Knight',
    assetPath: kKnightProfilePictureAsset,
  ),
  ProfilePictureOption(
    id: 'samurai',
    label: 'Samurai',
    assetPath: '$_kProfilePictureAssetRoot/profile_picture_samurai.png',
  ),
  ProfilePictureOption(
    id: 'viking',
    label: 'Viking',
    assetPath: '$_kProfilePictureAssetRoot/profile_picture_viking.png',
  ),
  ProfilePictureOption(
    id: 'shield-1',
    label: 'Shield 1',
    assetPath: '$_kProfilePictureAssetRoot/profile_picture_shield_1.png',
  ),
  ProfilePictureOption(
    id: 'shield-2',
    label: 'Shield 2',
    assetPath: '$_kProfilePictureAssetRoot/profile_picture_shield_2.png',
  ),
  ProfilePictureOption(
    id: 'dragon',
    label: 'Dragon',
    assetPath: '$_kProfilePictureAssetRoot/profile_picture_dragon.png',
  ),
  ProfilePictureOption(
    id: 'wizard',
    label: 'Wizard',
    assetPath: '$_kProfilePictureAssetRoot/profile_picture_wizard.png',
  ),
  ProfilePictureOption(
    id: 'chest',
    label: 'Chest',
    assetPath: '$_kProfilePictureAssetRoot/profile_picture_chest.png',
  ),
];

const _kZnsPrefix = 'zns-';

bool isZnsProfilePictureId(String id) => id.startsWith(_kZnsPrefix);

String _stripZnsPrefix(String id) =>
    id.startsWith(_kZnsPrefix) ? id.substring(_kZnsPrefix.length) : id;

ProfilePictureOption? findProfilePictureOption(String id) {
  final baseId = _stripZnsPrefix(id);
  for (final option in kProfilePictureOptions) {
    if (option.id == baseId) return option;
  }
  if (_legacyKnightIdPattern.hasMatch(baseId)) {
    return kProfilePictureOptions.first;
  }
  return null;
}

ProfilePictureOption resolveProfilePictureOption(String id) {
  return findProfilePictureOption(id) ??
      findProfilePictureOption(kDefaultProfilePictureId)!;
}

bool isKnownProfilePictureId(String id) {
  return findProfilePictureOption(id) != null;
}
