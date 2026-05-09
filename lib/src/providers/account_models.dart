import '../core/profile_pictures.dart';

class AccountInfo {
  final String uuid;
  final String name;
  final int order;
  final bool isHardware;
  final bool isSeedAnchor;
  final String profilePictureId;

  const AccountInfo({
    required this.uuid,
    required this.name,
    required this.order,
    this.isHardware = false,
    this.isSeedAnchor = false,
    this.profilePictureId = kDefaultProfilePictureId,
  });

  AccountInfo copyWith({
    String? name,
    int? order,
    bool? isSeedAnchor,
    String? profilePictureId,
  }) => AccountInfo(
    uuid: uuid,
    name: name ?? this.name,
    order: order ?? this.order,
    isHardware: isHardware,
    isSeedAnchor: isSeedAnchor ?? this.isSeedAnchor,
    profilePictureId: profilePictureId ?? this.profilePictureId,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'order': order,
    'isHardware': isHardware,
    'isSeedAnchor': isSeedAnchor,
    'profilePictureId': profilePictureId,
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
    uuid: json['uuid'] as String,
    name: json['name'] as String,
    order: json['order'] as int? ?? 0,
    isHardware: json['isHardware'] as bool? ?? false,
    isSeedAnchor:
        json['isSeedAnchor'] as bool? ??
        ((json['order'] as int? ?? 0) == 0 &&
            !(json['isHardware'] as bool? ?? false)),
    profilePictureId:
        json['profilePictureId'] as String? ?? kDefaultProfilePictureId,
  );
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
