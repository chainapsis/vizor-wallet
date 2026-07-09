import '../core/profile_pictures.dart';

class AccountInfo {
  final String uuid;
  final String name;
  final int order;
  final bool isHardware;
  final bool isSeedAnchor;
  final String profilePictureId;
  final String? walletLinkSourceAccountUuid;

  const AccountInfo({
    required this.uuid,
    required this.name,
    required this.order,
    this.isHardware = false,
    this.isSeedAnchor = false,
    this.profilePictureId = kDefaultProfilePictureId,
    this.walletLinkSourceAccountUuid,
  });

  AccountInfo copyWith({
    String? name,
    int? order,
    bool? isSeedAnchor,
    String? profilePictureId,
    String? walletLinkSourceAccountUuid,
  }) => AccountInfo(
    uuid: uuid,
    name: name ?? this.name,
    order: order ?? this.order,
    isHardware: isHardware,
    isSeedAnchor: isSeedAnchor ?? this.isSeedAnchor,
    profilePictureId: profilePictureId ?? this.profilePictureId,
    walletLinkSourceAccountUuid:
        walletLinkSourceAccountUuid ?? this.walletLinkSourceAccountUuid,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'order': order,
    'isHardware': isHardware,
    'isSeedAnchor': isSeedAnchor,
    'profilePictureId': profilePictureId,
    'walletLinkSourceAccountUuid': walletLinkSourceAccountUuid,
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
    uuid: json['uuid'] as String,
    name: json['name'] as String,
    order: json['order'] as int? ?? 0,
    isHardware: json['isHardware'] as bool? ?? false,
    // Legacy stored account JSON did not include this field. Runtime account
    // state is reconciled from Rust during bootstrap; this fallback only keeps
    // pre-field snapshots conservative until Rust metadata is available.
    isSeedAnchor:
        json['isSeedAnchor'] as bool? ??
        ((json['order'] as int? ?? 0) == 0 &&
            !(json['isHardware'] as bool? ?? false)),
    profilePictureId: normalizeProfilePictureId(
      json['profilePictureId'] as String? ?? kDefaultProfilePictureId,
    ),
    walletLinkSourceAccountUuid: _normalizedOptionalString(
      json['walletLinkSourceAccountUuid'],
    ),
  );
}

String? _normalizedOptionalString(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

class AccountState {
  final List<AccountInfo> accounts;
  final String? activeAccountUuid;
  final String? activeAddress;

  const AccountState({
    this.accounts = const [],
    this.activeAccountUuid,
    this.activeAddress,
  });

  bool get hasAccounts => accounts.isNotEmpty;

  AccountInfo? get activeAccount {
    if (activeAccountUuid == null) return null;
    for (final a in accounts) {
      if (a.uuid == activeAccountUuid) return a;
    }
    return null;
  }

  AccountState copyWith({
    List<AccountInfo>? accounts,
    String? activeAccountUuid,
    String? activeAddress,
  }) => AccountState(
    accounts: accounts ?? this.accounts,
    activeAccountUuid: activeAccountUuid ?? this.activeAccountUuid,
    activeAddress: activeAddress ?? this.activeAddress,
  );
}
