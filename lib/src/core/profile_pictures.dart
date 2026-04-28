const kDefaultProfilePictureId = 'knight-02';
const kKnightProfilePictureAsset =
    'assets/illustrations/sidebar_account_avatar_knight.png';

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

// Figma currently hands off the same Knight image for every slot. Keep stable
// ids now so each asset can be swapped later without changing stored values.
final kProfilePictureOptions = List<ProfilePictureOption>.unmodifiable(
  List.generate(
    15,
    (index) => ProfilePictureOption(
      id: 'knight-${index.toString().padLeft(2, '0')}',
      label: 'Knight',
      assetPath: kKnightProfilePictureAsset,
    ),
  ),
);

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
