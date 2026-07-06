import 'dart:convert';
import 'dart:typed_data';

import '../../../features/address_book/models/address_book_contact.dart';
import '../../../providers/account_provider.dart';
import '../wallet_link_config.dart';

class WalletLinkEnvelope {
  const WalletLinkEnvelope({
    required this.algorithm,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });

  final String algorithm;
  final String nonce;
  final String ciphertext;
  final String tag;

  Map<String, Object?> toJson() => {
    'algorithm': algorithm,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'tag': tag,
  };

  factory WalletLinkEnvelope.fromJson(Map<String, Object?> json) {
    return WalletLinkEnvelope(
      algorithm: json['algorithm'] as String,
      nonce: json['nonce'] as String,
      ciphertext: json['ciphertext'] as String,
      tag: json['tag'] as String,
    );
  }
}

class WalletLinkCreatePackageRequest {
  const WalletLinkCreatePackageRequest({
    required this.id,
    required this.envelope,
  });

  final String id;
  final WalletLinkEnvelope envelope;

  Map<String, Object?> toJson() => {
    'id': id,
    'version': 1,
    'envelope': envelope.toJson(),
  };
}

class WalletLinkCreatePackageResponse {
  const WalletLinkCreatePackageResponse({
    required this.id,
    required this.expiresAt,
    required this.ttlSeconds,
  });

  final String id;
  final int expiresAt;
  final int ttlSeconds;

  factory WalletLinkCreatePackageResponse.fromJson(Map<String, Object?> json) {
    return WalletLinkCreatePackageResponse(
      id: json['id'] as String,
      expiresAt: (json['expiresAt'] as num).toInt(),
      ttlSeconds: (json['ttlSeconds'] as num).toInt(),
    );
  }
}

class WalletLinkPackageDownload {
  const WalletLinkPackageDownload({
    required this.id,
    required this.version,
    required this.createdAt,
    required this.expiresAt,
    required this.envelope,
  });

  final String id;
  final int version;
  final int createdAt;
  final int expiresAt;
  final WalletLinkEnvelope envelope;

  factory WalletLinkPackageDownload.fromJson(Map<String, Object?> json) {
    return WalletLinkPackageDownload(
      id: json['id'] as String,
      version: (json['version'] as num).toInt(),
      createdAt: (json['createdAt'] as num).toInt(),
      expiresAt: (json['expiresAt'] as num).toInt(),
      envelope: WalletLinkEnvelope.fromJson(
        Map<String, Object?>.from(json['envelope'] as Map),
      ),
    );
  }
}

class WalletLinkPackageUpload {
  const WalletLinkPackageUpload({
    required this.packageId,
    required this.qrPayload,
    required this.accountCount,
    required this.contactCount,
  });

  final String packageId;
  final String qrPayload;
  final int accountCount;
  final int contactCount;
}

class WalletLinkQrPayload {
  const WalletLinkQrPayload({required this.packageId, required this.keyBytes});

  final String packageId;
  final Uint8List keyBytes;

  static WalletLinkQrPayload parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'vizor' ||
        uri.host != 'wallet-link' ||
        uri.path != '/v1') {
      throw const FormatException('Not a Vizor wallet link QR payload.');
    }

    final packageId = uri.queryParameters['id']?.trim();
    final key = uri.queryParameters['key']?.trim();
    if (packageId == null ||
        packageId.isEmpty ||
        !kWalletLinkPackageIdRegex.hasMatch(packageId) ||
        key == null ||
        key.isEmpty) {
      throw const FormatException(
        'Vizor wallet link QR payload is incomplete.',
      );
    }

    final keyBytes = Uint8List.fromList(_base64UrlNoPaddingDecode(key));
    if (keyBytes.length != 32) {
      throw const FormatException('Vizor wallet link key must be 32 bytes.');
    }

    return WalletLinkQrPayload(
      packageId: packageId.toLowerCase(),
      keyBytes: keyBytes,
    );
  }
}

class WalletLinkTransferPayload {
  const WalletLinkTransferPayload({
    required this.version,
    required this.exportedAt,
    required this.network,
    required this.activeAccountUuid,
    required this.accounts,
    required this.contacts,
  });

  final int version;
  final DateTime? exportedAt;
  final String network;
  final String? activeAccountUuid;
  final List<WalletLinkTransferAccount> accounts;
  final List<AddressBookContact> contacts;

  factory WalletLinkTransferPayload.fromJson(Map<String, Object?> json) {
    final accountsRaw = json['accounts'];
    final contactsRaw = json['contacts'];
    if (accountsRaw is! List || contactsRaw is! List) {
      throw const FormatException('Wallet link payload is missing data.');
    }

    return WalletLinkTransferPayload(
      version: (json['version'] as num?)?.toInt() ?? 0,
      exportedAt: DateTime.tryParse((json['exportedAt'] as String?) ?? ''),
      network: ((json['network'] as String?) ?? '').trim(),
      activeAccountUuid: (json['activeAccountUuid'] as String?)?.trim(),
      accounts: [
        for (final item in accountsRaw)
          if (item is Map)
            WalletLinkTransferAccount.fromJson(Map<String, Object?>.from(item)),
      ],
      contacts: [
        for (final item in contactsRaw)
          if (item is Map)
            ?AddressBookContact.tryFromJson(Map<String, Object?>.from(item)),
      ],
    );
  }

  List<WalletLinkTransferAccount> get importableAccounts => [
    for (final account in accounts)
      if (account.isImportable) account,
  ];
}

class WalletLinkTransferAccount {
  const WalletLinkTransferAccount({
    required this.uuid,
    required this.name,
    required this.order,
    required this.isHardware,
    required this.isSeedAnchor,
    required this.profilePictureId,
    required this.birthdayHeight,
    required this.zip32AccountIndex,
    required this.ufvk,
    required this.seedFingerprint,
    required this.mnemonic,
  });

  final String uuid;
  final String name;
  final int order;
  final bool isHardware;
  final bool isSeedAnchor;
  final String? profilePictureId;
  final int? birthdayHeight;
  final int? zip32AccountIndex;
  final String? ufvk;
  final List<int>? seedFingerprint;
  final String? mnemonic;

  factory WalletLinkTransferAccount.fromJson(Map<String, Object?> json) {
    return WalletLinkTransferAccount(
      uuid: ((json['uuid'] as String?) ?? '').trim(),
      name: ((json['name'] as String?) ?? '').trim(),
      order: (json['order'] as num?)?.toInt() ?? 0,
      isHardware: json['isHardware'] as bool? ?? false,
      isSeedAnchor: json['isSeedAnchor'] as bool? ?? false,
      profilePictureId: (json['profilePictureId'] as String?)?.trim(),
      birthdayHeight: (json['birthdayHeight'] as num?)?.toInt(),
      zip32AccountIndex: (json['zip32AccountIndex'] as num?)?.toInt(),
      ufvk: (json['ufvk'] as String?)?.trim(),
      seedFingerprint: (json['seedFingerprint'] as List?)
          ?.map((value) => (value as num).toInt())
          .toList(),
      mnemonic: (json['mnemonic'] as String?)?.trim(),
    );
  }

  String get displayName => name.isEmpty ? 'Account ${order + 1}' : name;

  bool get isImportable {
    if (birthdayHeight == null || zip32AccountIndex == null) return false;
    if (isHardware) {
      return ufvk != null &&
          ufvk!.isNotEmpty &&
          seedFingerprint != null &&
          seedFingerprint!.length == 32;
    }
    return mnemonic != null && mnemonic!.isNotEmpty;
  }

  LinkedWalletAccountImport toAccountImport() {
    if (!isImportable) {
      throw StateError('Wallet link account is not importable: $displayName');
    }

    return LinkedWalletAccountImport(
      name: displayName,
      birthdayHeight: birthdayHeight!,
      zip32AccountIndex: zip32AccountIndex!,
      isHardware: isHardware,
      isSeedAnchor: isSeedAnchor,
      mnemonic: mnemonic,
      ufvk: ufvk,
      seedFingerprint: seedFingerprint,
      profilePictureId: profilePictureId,
    );
  }
}

enum WalletLinkPhase { idle, preparing, ready, linked, expired, error }

class WalletLinkState {
  const WalletLinkState({
    required this.phase,
    this.qrPayload,
    this.packageId,
    this.expiresAt,
    this.remaining = Duration.zero,
    this.accountCount = 0,
    this.contactCount = 0,
    this.errorMessage,
  });

  const WalletLinkState.initial()
    : phase = WalletLinkPhase.idle,
      qrPayload = null,
      packageId = null,
      expiresAt = null,
      remaining = Duration.zero,
      accountCount = 0,
      contactCount = 0,
      errorMessage = null;

  final WalletLinkPhase phase;
  final String? qrPayload;
  final String? packageId;
  final DateTime? expiresAt;
  final Duration remaining;
  final int accountCount;
  final int contactCount;
  final String? errorMessage;

  bool get isPreparing => phase == WalletLinkPhase.preparing;

  WalletLinkState copyWith({
    WalletLinkPhase? phase,
    String? qrPayload,
    bool clearQrPayload = false,
    String? packageId,
    bool clearPackageId = false,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    Duration? remaining,
    int? accountCount,
    int? contactCount,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return WalletLinkState(
      phase: phase ?? this.phase,
      qrPayload: clearQrPayload ? null : qrPayload ?? this.qrPayload,
      packageId: clearPackageId ? null : packageId ?? this.packageId,
      expiresAt: clearExpiresAt ? null : expiresAt ?? this.expiresAt,
      remaining: remaining ?? this.remaining,
      accountCount: accountCount ?? this.accountCount,
      contactCount: contactCount ?? this.contactCount,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

List<int> _base64UrlNoPaddingDecode(String value) {
  final normalized = base64Url.normalize(value);
  return base64Url.decode(normalized);
}
