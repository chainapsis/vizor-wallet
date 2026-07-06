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
