import '../core/profile_pictures.dart';

enum AccountKind {
  software,
  hardware,
  multisig;

  static AccountKind parse(String? value, {required bool legacyIsHardware}) {
    return switch (value) {
      'software' => AccountKind.software,
      'hardware' => AccountKind.hardware,
      'multisig' => AccountKind.multisig,
      _ => legacyIsHardware ? AccountKind.hardware : AccountKind.software,
    };
  }
}

class AccountInfo {
  final String uuid;
  final String name;
  final int order;
  final AccountKind kind;
  final bool isSeedAnchor;
  final String profilePictureId;

  const AccountInfo({
    required this.uuid,
    required this.name,
    required this.order,
    bool isHardware = false,
    AccountKind? kind,
    this.isSeedAnchor = false,
    this.profilePictureId = kDefaultProfilePictureId,
  }) : kind =
           kind ?? (isHardware ? AccountKind.hardware : AccountKind.software);

  bool get isSoftware => kind == AccountKind.software;
  bool get isHardware => kind == AccountKind.hardware;
  bool get isMultisig => kind == AccountKind.multisig;
  bool get hasLocalMnemonic => isSoftware;
  bool get supportsSeedPhraseReveal => hasLocalMnemonic;
  bool get supportsSoftwareSigning => hasLocalMnemonic;

  AccountInfo copyWith({
    String? name,
    int? order,
    AccountKind? kind,
    bool? isSeedAnchor,
    String? profilePictureId,
  }) => AccountInfo(
    uuid: uuid,
    name: name ?? this.name,
    order: order ?? this.order,
    kind: kind ?? this.kind,
    isSeedAnchor: isSeedAnchor ?? this.isSeedAnchor,
    profilePictureId: profilePictureId ?? this.profilePictureId,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'order': order,
    'isHardware': isHardware,
    'kind': kind.name,
    'isSeedAnchor': isSeedAnchor,
    'profilePictureId': profilePictureId,
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    final legacyIsHardware = json['isHardware'] as bool? ?? false;
    final kind = AccountKind.parse(
      json['kind'] as String?,
      legacyIsHardware: legacyIsHardware,
    );
    return AccountInfo(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      order: json['order'] as int? ?? 0,
      kind: kind,
      // Legacy stored account JSON did not include this field. Runtime account
      // state is reconciled from Rust during bootstrap; this fallback only keeps
      // pre-field snapshots conservative until Rust metadata is available.
      isSeedAnchor:
          json['isSeedAnchor'] as bool? ??
          ((json['order'] as int? ?? 0) == 0 && kind == AccountKind.software),
      profilePictureId: normalizeProfilePictureId(
        json['profilePictureId'] as String? ?? kDefaultProfilePictureId,
      ),
    );
  }
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
