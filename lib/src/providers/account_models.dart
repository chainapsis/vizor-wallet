import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/profile_pictures.dart';

enum HardwareSignerKind {
  keystone,
  ledger;

  static HardwareSignerKind? fromJson(Object? value) {
    if (value is! String) return null;
    return switch (value.trim().toLowerCase()) {
      'keystone' => HardwareSignerKind.keystone,
      'ledger' => HardwareSignerKind.ledger,
      _ => null,
    };
  }
}

enum LedgerConnectionPreference {
  automatic,
  usb,
  bluetooth;

  static LedgerConnectionPreference fromJson(Object? value) {
    if (value is! String) return LedgerConnectionPreference.automatic;
    return switch (value.trim().toLowerCase()) {
      'usb' => LedgerConnectionPreference.usb,
      'bluetooth' => LedgerConnectionPreference.bluetooth,
      _ => LedgerConnectionPreference.automatic,
    };
  }
}

enum LedgerConnectionTransport {
  usb,
  bluetooth;

  static LedgerConnectionTransport? fromJson(Object? value) {
    if (value is! String) return null;
    return switch (value.trim().toLowerCase()) {
      'usb' => LedgerConnectionTransport.usb,
      'bluetooth' => LedgerConnectionTransport.bluetooth,
      _ => null,
    };
  }
}

class AccountInfo {
  final String uuid;
  final String name;
  final int order;
  final bool isHardware;
  final HardwareSignerKind? hardwareSignerKind;
  final int? birthdayHeight;
  final int? zip32AccountIndex;
  final LedgerConnectionPreference ledgerConnectionPreference;
  final LedgerConnectionTransport? ledgerLastTransport;
  final String? ledgerDeviceId;
  final String? ledgerDeviceName;
  final String? ledgerDeviceModel;
  final String? ledgerWalletFingerprint;
  final String? ledgerWalletName;
  final bool isSeedAnchor;
  final String profilePictureId;
  final String? walletLinkSourceAccountUuid;

  const AccountInfo({
    required this.uuid,
    required this.name,
    required this.order,
    this.isHardware = false,
    HardwareSignerKind? hardwareSignerKind,
    this.birthdayHeight,
    this.zip32AccountIndex,
    this.ledgerConnectionPreference = LedgerConnectionPreference.automatic,
    this.ledgerLastTransport,
    this.ledgerDeviceId,
    this.ledgerDeviceName,
    this.ledgerDeviceModel,
    this.ledgerWalletFingerprint,
    this.ledgerWalletName,
    this.isSeedAnchor = false,
    this.profilePictureId = kDefaultProfilePictureId,
    this.walletLinkSourceAccountUuid,
  }) : hardwareSignerKind =
           hardwareSignerKind ??
           (isHardware ? HardwareSignerKind.keystone : null);

  bool get isKeystone =>
      isHardware && hardwareSignerKind == HardwareSignerKind.keystone;

  bool get isLedger =>
      isHardware && hardwareSignerKind == HardwareSignerKind.ledger;

  bool get hasLedgerWalletIdentity {
    final fingerprint = ledgerWalletFingerprint?.trim();
    return isLedger &&
        fingerprint != null &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint);
  }

  AccountInfo copyWith({
    String? name,
    int? order,
    bool? isSeedAnchor,
    HardwareSignerKind? hardwareSignerKind,
    int? birthdayHeight,
    int? zip32AccountIndex,
    LedgerConnectionPreference? ledgerConnectionPreference,
    LedgerConnectionTransport? ledgerLastTransport,
    String? ledgerDeviceId,
    String? ledgerDeviceName,
    String? ledgerDeviceModel,
    String? ledgerWalletFingerprint,
    String? ledgerWalletName,
    String? profilePictureId,
    String? walletLinkSourceAccountUuid,
  }) => AccountInfo(
    uuid: uuid,
    name: name ?? this.name,
    order: order ?? this.order,
    isHardware: isHardware,
    hardwareSignerKind: hardwareSignerKind ?? this.hardwareSignerKind,
    birthdayHeight: birthdayHeight ?? this.birthdayHeight,
    zip32AccountIndex: zip32AccountIndex ?? this.zip32AccountIndex,
    ledgerConnectionPreference:
        ledgerConnectionPreference ?? this.ledgerConnectionPreference,
    ledgerLastTransport: ledgerLastTransport ?? this.ledgerLastTransport,
    ledgerDeviceId: ledgerDeviceId ?? this.ledgerDeviceId,
    ledgerDeviceName: ledgerDeviceName ?? this.ledgerDeviceName,
    ledgerDeviceModel: ledgerDeviceModel ?? this.ledgerDeviceModel,
    ledgerWalletFingerprint:
        ledgerWalletFingerprint ?? this.ledgerWalletFingerprint,
    ledgerWalletName: ledgerWalletName ?? this.ledgerWalletName,
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
    'hardwareSignerKind': hardwareSignerKind?.name,
    'birthdayHeight': birthdayHeight,
    'zip32AccountIndex': zip32AccountIndex,
    'ledgerConnectionPreference': isLedger
        ? ledgerConnectionPreference.name
        : null,
    'ledgerLastTransport': isLedger ? ledgerLastTransport?.name : null,
    'ledgerDeviceId': isLedger ? ledgerDeviceId : null,
    'ledgerDeviceName': isLedger ? ledgerDeviceName : null,
    'ledgerDeviceModel': isLedger ? ledgerDeviceModel : null,
    'ledgerWalletFingerprint': isLedger ? ledgerWalletFingerprint : null,
    'ledgerWalletName': isLedger ? ledgerWalletName : null,
    'isSeedAnchor': isSeedAnchor,
    'profilePictureId': profilePictureId,
    'walletLinkSourceAccountUuid': walletLinkSourceAccountUuid,
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    final isHardware = json['isHardware'] as bool? ?? false;
    return AccountInfo(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      order: json['order'] as int? ?? 0,
      isHardware: isHardware,
      hardwareSignerKind: isHardware
          ? HardwareSignerKind.fromJson(json['hardwareSignerKind']) ??
                HardwareSignerKind.keystone
          : null,
      birthdayHeight: json['birthdayHeight'] as int?,
      zip32AccountIndex: json['zip32AccountIndex'] as int?,
      ledgerConnectionPreference: LedgerConnectionPreference.fromJson(
        json['ledgerConnectionPreference'],
      ),
      ledgerLastTransport: LedgerConnectionTransport.fromJson(
        json['ledgerLastTransport'],
      ),
      ledgerDeviceId: _normalizedOptionalString(json['ledgerDeviceId']),
      ledgerDeviceName: _normalizedOptionalString(json['ledgerDeviceName']),
      ledgerDeviceModel: _normalizedOptionalString(json['ledgerDeviceModel']),
      ledgerWalletFingerprint: _normalizedOptionalString(
        json['ledgerWalletFingerprint'],
      ),
      ledgerWalletName: _normalizedOptionalString(json['ledgerWalletName']),
      // Legacy stored account JSON did not include this field. Runtime account
      // state is reconciled from Rust during bootstrap; this fallback only keeps
      // pre-field snapshots conservative until Rust metadata is available.
      isSeedAnchor:
          json['isSeedAnchor'] as bool? ??
          ((json['order'] as int? ?? 0) == 0 && !isHardware),
      profilePictureId: normalizeProfilePictureId(
        json['profilePictureId'] as String? ?? kDefaultProfilePictureId,
      ),
      walletLinkSourceAccountUuid: _normalizedOptionalString(
        json['walletLinkSourceAccountUuid'],
      ),
    );
  }
}

enum AccountFamilyKind { ledger, standalone }

/// A presentation-only grouping of accounts that share a verified signer
/// identity. Family membership is derived from existing account metadata and
/// is not persisted independently.
class AccountFamily {
  final String stableKey;
  final AccountFamilyKind kind;
  final List<AccountInfo> accounts;
  final String name;

  AccountFamily({
    required this.stableKey,
    required this.kind,
    required this.name,
    required List<AccountInfo> accounts,
  }) : accounts = List.unmodifiable(accounts);

  bool get isLedger => kind == AccountFamilyKind.ledger;
}

/// Groups accounts by authenticated signer identity while preserving the
/// input order of both families and their members.
///
/// Ledger accounts with a 32-byte hex fingerprint are grouped by that
/// identity. Ledger accounts without one remain isolated, as do all other
/// accounts.
List<AccountFamily> resolveAccountFamilies(Iterable<AccountInfo> accounts) {
  final builders = <String, _AccountFamilyBuilder>{};

  for (final account in accounts) {
    final fingerprint = _verifiedLedgerWalletFingerprint(account);
    if (fingerprint == null) {
      final key = 'account:${account.uuid}';
      builders[key] = _AccountFamilyBuilder(
        stableKey: key,
        kind: AccountFamilyKind.standalone,
        name: account.name,
        accounts: [account],
      );
      continue;
    }

    final stableKey = 'ledger:${sha256.convert(utf8.encode(fingerprint))}';
    final builder = builders.putIfAbsent(
      stableKey,
      () => _AccountFamilyBuilder(
        stableKey: stableKey,
        kind: AccountFamilyKind.ledger,
        name: account.ledgerWalletName ?? 'Ledger wallet',
      ),
    );
    builder.accounts.add(account);
  }

  return builders.values
      .map((builder) => builder.build())
      .toList(growable: false);
}

String? _verifiedLedgerWalletFingerprint(AccountInfo account) {
  if (!account.hasLedgerWalletIdentity) return null;
  final fingerprint = account.ledgerWalletFingerprint?.trim().toLowerCase();
  return fingerprint;
}

class _AccountFamilyBuilder {
  final String stableKey;
  final AccountFamilyKind kind;
  final List<AccountInfo> accounts;
  final String name;

  _AccountFamilyBuilder({
    required this.stableKey,
    required this.kind,
    required this.name,
    List<AccountInfo>? accounts,
  }) : accounts = accounts ?? [];

  AccountFamily build() => AccountFamily(
    stableKey: stableKey,
    kind: kind,
    name: name,
    accounts: accounts,
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
