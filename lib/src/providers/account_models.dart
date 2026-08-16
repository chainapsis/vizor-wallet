import '../core/profile_pictures.dart';

class AccountInfo {
  final String uuid;
  final String name;
  final int order;
  final bool isHardware;
  final bool isSeedAnchor;
  final String profilePictureId;
  final String? walletLinkSourceAccountUuid;
  final String? seedFamilyId;
  final String? accountGroupName;

  const AccountInfo({
    required this.uuid,
    required this.name,
    required this.order,
    this.isHardware = false,
    this.isSeedAnchor = false,
    this.profilePictureId = kDefaultProfilePictureId,
    this.walletLinkSourceAccountUuid,
    this.seedFamilyId,
    this.accountGroupName,
  });

  AccountInfo copyWith({
    String? name,
    int? order,
    bool? isSeedAnchor,
    String? profilePictureId,
    String? walletLinkSourceAccountUuid,
    String? seedFamilyId,
    String? accountGroupName,
  }) => AccountInfo(
    uuid: uuid,
    name: name ?? this.name,
    order: order ?? this.order,
    isHardware: isHardware,
    isSeedAnchor: isSeedAnchor ?? this.isSeedAnchor,
    profilePictureId: profilePictureId ?? this.profilePictureId,
    walletLinkSourceAccountUuid:
        walletLinkSourceAccountUuid ?? this.walletLinkSourceAccountUuid,
    seedFamilyId: seedFamilyId ?? this.seedFamilyId,
    accountGroupName: accountGroupName ?? this.accountGroupName,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'order': order,
    'isHardware': isHardware,
    'isSeedAnchor': isSeedAnchor,
    'profilePictureId': profilePictureId,
    'walletLinkSourceAccountUuid': walletLinkSourceAccountUuid,
    'seedFamilyId': seedFamilyId,
    'accountGroupName': accountGroupName,
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
    seedFamilyId: _normalizedOptionalString(json['seedFamilyId']),
    accountGroupName: _normalizedOptionalString(json['accountGroupName']),
  );
}

/// A display-only group of accounts backed by the same ZIP-32 seed.
///
/// Hardware accounts and accounts without derivation metadata are intentionally
/// isolated so hardware/legacy accounts are never grouped by accident.
class AccountFamily {
  const AccountFamily({
    required this.anchorAccountUuid,
    required this.name,
    required this.accounts,
    required this.containsActiveAccount,
  });

  final String anchorAccountUuid;
  final String name;
  final List<AccountInfo> accounts;
  final bool containsActiveAccount;
}

/// Resolves the current account for account-management presentation.
///
/// Persisted active-account metadata can briefly outlive a removed account.
/// In that case, both form factors present the first account in creation order
/// as current until the provider reconciles the stored value.
AccountInfo? resolveActiveAccountForDisplay(
  List<AccountInfo> accounts,
  String? activeAccountUuid,
) {
  if (accounts.isEmpty) return null;
  for (final account in accounts) {
    if (account.uuid == activeAccountUuid) return account;
  }

  return accounts.indexed.reduce((first, second) {
    final order = first.$2.order.compareTo(second.$2.order);
    return order < 0 || (order == 0 && first.$1 < second.$1) ? first : second;
  }).$2;
}

List<AccountFamily> groupAccountsBySeedFamily(
  List<AccountInfo> accounts,
  String? activeAccountUuid,
) {
  final indexedAccounts = accounts.indexed.toList()
    ..sort((left, right) {
      final order = left.$2.order.compareTo(right.$2.order);
      return order != 0 ? order : left.$1.compareTo(right.$1);
    });
  final grouped = <String, List<AccountInfo>>{};
  for (final (_, account) in indexedAccounts) {
    final seedFamilyId = _normalizedOptionalString(account.seedFamilyId);
    final key = account.isHardware || seedFamilyId == null
        ? 'account:${account.uuid}'
        : 'seed:$seedFamilyId';
    grouped.putIfAbsent(key, () => []).add(account);
  }

  final families = <AccountFamily>[];
  for (final familyAccounts in grouped.values) {
    final containsActive = familyAccounts.any(
      (account) => account.uuid == activeAccountUuid,
    );
    final displayAccounts = containsActive
        ? [
            ...familyAccounts.where(
              (account) => account.uuid == activeAccountUuid,
            ),
            ...familyAccounts.where(
              (account) => account.uuid != activeAccountUuid,
            ),
          ]
        : familyAccounts;
    families.add(
      AccountFamily(
        anchorAccountUuid: familyAccounts.first.uuid,
        name: _accountFamilyName(familyAccounts, families.length + 1),
        accounts: displayAccounts,
        containsActiveAccount: containsActive,
      ),
    );
  }

  final activeFamilyIndex = families.indexWhere(
    (family) => family.containsActiveAccount,
  );
  if (activeFamilyIndex > 0) {
    final activeFamily = families.removeAt(activeFamilyIndex);
    families.insert(0, activeFamily);
  }
  return families;
}

String _accountFamilyName(List<AccountInfo> accounts, int familyNumber) {
  for (final account in accounts) {
    final customName = _normalizedOptionalString(account.accountGroupName);
    if (customName != null) return customName;
  }
  return 'Wallet $familyNumber';
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
