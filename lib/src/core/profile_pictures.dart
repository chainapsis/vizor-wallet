const kDefaultProfilePictureId = 'pfp-01';
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
  for (final option in kProfilePictureOptions) {
    if (option.id == id) return option;
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
