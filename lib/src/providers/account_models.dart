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
  final LedgerConnectionTransport? ledgerLastTransport;
  final String? ledgerDeviceId;
  final String? ledgerDeviceName;
  final String? ledgerDeviceModel;
  final bool isSeedAnchor;
  final String profilePictureId;
  final String? walletLinkSourceAccountUuid;

  /// Whether this account still needs to back up its secret passphrase.
  final bool setupPending;

  /// Whether the deferred Zcash introduction is still offered on Home.
  final bool giftEducationPending;

  /// Keeps the Home backup prompt hidden until this UTC instant. The backup
  /// itself remains incomplete while this is set.
  final DateTime? backupReminderSnoozedUntilUtc;

  /// Number of times the backup prompt was deferred. Three represents the
  /// third and every later deferral so the reminder cadence stays bounded.
  final int backupReminderSnoozeCount;

  const AccountInfo({
    required this.uuid,
    required this.name,
    required this.order,
    this.isHardware = false,
    HardwareSignerKind? hardwareSignerKind,
    this.birthdayHeight,
    this.zip32AccountIndex,
    this.ledgerLastTransport,
    this.ledgerDeviceId,
    this.ledgerDeviceName,
    this.ledgerDeviceModel,
    this.isSeedAnchor = false,
    this.profilePictureId = kDefaultProfilePictureId,
    this.walletLinkSourceAccountUuid,
    this.setupPending = false,
    this.giftEducationPending = false,
    this.backupReminderSnoozedUntilUtc,
    this.backupReminderSnoozeCount = 0,
  }) : hardwareSignerKind =
           hardwareSignerKind ??
           (isHardware ? HardwareSignerKind.keystone : null);

  bool get isKeystone =>
      isHardware && hardwareSignerKind == HardwareSignerKind.keystone;

  bool get isLedger =>
      isHardware && hardwareSignerKind == HardwareSignerKind.ledger;

  AccountInfo copyWith({
    String? name,
    int? order,
    bool? isSeedAnchor,
    HardwareSignerKind? hardwareSignerKind,
    int? birthdayHeight,
    int? zip32AccountIndex,
    LedgerConnectionTransport? ledgerLastTransport,
    String? ledgerDeviceId,
    String? ledgerDeviceName,
    String? ledgerDeviceModel,
    String? profilePictureId,
    String? walletLinkSourceAccountUuid,
    bool? setupPending,
    bool? giftEducationPending,
    DateTime? backupReminderSnoozedUntilUtc,
    bool clearBackupReminderSnooze = false,
    int? backupReminderSnoozeCount,
  }) => AccountInfo(
    uuid: uuid,
    name: name ?? this.name,
    order: order ?? this.order,
    isHardware: isHardware,
    hardwareSignerKind: hardwareSignerKind ?? this.hardwareSignerKind,
    birthdayHeight: birthdayHeight ?? this.birthdayHeight,
    zip32AccountIndex: zip32AccountIndex ?? this.zip32AccountIndex,
    ledgerLastTransport: ledgerLastTransport ?? this.ledgerLastTransport,
    ledgerDeviceId: ledgerDeviceId ?? this.ledgerDeviceId,
    ledgerDeviceName: ledgerDeviceName ?? this.ledgerDeviceName,
    ledgerDeviceModel: ledgerDeviceModel ?? this.ledgerDeviceModel,
    isSeedAnchor: isSeedAnchor ?? this.isSeedAnchor,
    profilePictureId: profilePictureId ?? this.profilePictureId,
    walletLinkSourceAccountUuid:
        walletLinkSourceAccountUuid ?? this.walletLinkSourceAccountUuid,
    setupPending: setupPending ?? this.setupPending,
    giftEducationPending: giftEducationPending ?? this.giftEducationPending,
    backupReminderSnoozedUntilUtc: clearBackupReminderSnooze
        ? null
        : backupReminderSnoozedUntilUtc ?? this.backupReminderSnoozedUntilUtc,
    backupReminderSnoozeCount: clearBackupReminderSnooze
        ? 0
        : backupReminderSnoozeCount ?? this.backupReminderSnoozeCount,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'order': order,
    'isHardware': isHardware,
    'hardwareSignerKind': hardwareSignerKind?.name,
    'birthdayHeight': birthdayHeight,
    'zip32AccountIndex': zip32AccountIndex,
    'ledgerLastTransport': isLedger ? ledgerLastTransport?.name : null,
    'ledgerDeviceId': isLedger ? ledgerDeviceId : null,
    'ledgerDeviceName': isLedger ? ledgerDeviceName : null,
    'ledgerDeviceModel': isLedger ? ledgerDeviceModel : null,
    'isSeedAnchor': isSeedAnchor,
    'profilePictureId': profilePictureId,
    'walletLinkSourceAccountUuid': walletLinkSourceAccountUuid,
    if (setupPending) 'setupPending': true,
    if (giftEducationPending) 'giftEducationPending': true,
    if (backupReminderSnoozedUntilUtc case final snoozedUntil?)
      'backupReminderSnoozedUntilUtc': snoozedUntil.toUtc().toIso8601String(),
    if (backupReminderSnoozeCount > 0)
      'backupReminderSnoozeCount': backupReminderSnoozeCount,
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
      ledgerLastTransport: LedgerConnectionTransport.fromJson(
        json['ledgerLastTransport'],
      ),
      ledgerDeviceId: _normalizedOptionalString(json['ledgerDeviceId']),
      ledgerDeviceName: _normalizedOptionalString(json['ledgerDeviceName']),
      ledgerDeviceModel: _normalizedOptionalString(json['ledgerDeviceModel']),
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
      setupPending: json['setupPending'] == true,
      giftEducationPending: json['giftEducationPending'] == true,
      backupReminderSnoozedUntilUtc: _dateTimeUtcFromJson(
        json['backupReminderSnoozedUntilUtc'],
      ),
      backupReminderSnoozeCount: _backupReminderSnoozeCountFromJson(
        json['backupReminderSnoozeCount'],
      ),
    );
  }
}

const kBackupReminderFirstDelay = Duration(days: 2);
const kBackupReminderSecondDelay = Duration(days: 14);
const kBackupReminderLaterDelay = Duration(days: 30);

Duration backupReminderDelayForCount(int count) => switch (count) {
  <= 1 => kBackupReminderFirstDelay,
  2 => kBackupReminderSecondDelay,
  _ => kBackupReminderLaterDelay,
};

DateTime? _dateTimeUtcFromJson(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

int _backupReminderSnoozeCountFromJson(Object? value) {
  if (value is! int) return 0;
  return value.clamp(0, 3).toInt();
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
