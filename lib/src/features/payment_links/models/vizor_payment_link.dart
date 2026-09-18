import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/navigation/vizor_deep_link.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;

part 'compact_payment_link_codec.dart';

const kPaymentLinkRegtestEnabledEnvKey = 'VIZOR_PAYMENT_LINK_REGTEST_ENABLED';
const kPaymentLinkRegtestEnabled = bool.fromEnvironment(
  kPaymentLinkRegtestEnabledEnvKey,
  defaultValue: false,
);

/// Display-only value captured at card creation or claim time.
/// It never participates in funding or claim calculations.
class PaymentLinkFiatSnapshot {
  const PaymentLinkFiatSnapshot({required this.amount, this.currency = 'USD'});

  static PaymentLinkFiatSnapshot? capture({
    required BigInt amountZatoshi,
    required double? zecUsdUnitPrice,
  }) {
    if (amountZatoshi <= BigInt.zero ||
        zecUsdUnitPrice == null ||
        !zecUsdUnitPrice.isFinite ||
        zecUsdUnitPrice <= 0) {
      return null;
    }
    final amount =
        amountZatoshi.toDouble() / zatoshiPerZec.toDouble() * zecUsdUnitPrice;
    return amount.isFinite ? PaymentLinkFiatSnapshot(amount: amount) : null;
  }

  final double amount;
  final String currency;

  Map<String, Object?> toPayload() {
    _validate();
    return {'amount': amount, 'currency': currency};
  }

  static PaymentLinkFiatSnapshot? fromPayload(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic> ||
        value['amount'] is! num ||
        value['currency'] is! String) {
      throw const FormatException('Gift Card fiat value is invalid.');
    }
    final snapshot = PaymentLinkFiatSnapshot(
      amount: (value['amount'] as num).toDouble(),
      currency: value['currency'] as String,
    );
    snapshot._validate();
    return snapshot;
  }

  void _validate() {
    if (!amount.isFinite || amount < 0 || currency != 'USD') {
      throw const FormatException('Gift Card fiat value is invalid.');
    }
  }
}

class PaymentLinkPresentation {
  const PaymentLinkPresentation({
    this.artworkId,
    this.message,
    this.fiatSnapshot,
  });

  static const maxArtworkIdLength = 64;
  static const maxMessageCharacters = 128;
  static const maxMessageUtf8Bytes = 512;

  final String? artworkId;
  final String? message;
  final PaymentLinkFiatSnapshot? fiatSnapshot;

  static bool isMessageWithinUtf8ByteLimit(String? message) {
    final normalizedMessage = _normalizeOptionalString(message);
    return normalizedMessage == null ||
        utf8.encode(normalizedMessage).length <= maxMessageUtf8Bytes;
  }

  Map<String, Object?>? toPayload() {
    final normalizedArtworkId = _normalizeOptionalString(artworkId);
    final normalizedMessage = _normalizeOptionalString(message);
    _validate(artworkId: normalizedArtworkId, message: normalizedMessage);
    if (normalizedArtworkId == null &&
        normalizedMessage == null &&
        fiatSnapshot == null) {
      return null;
    }
    return <String, Object?>{
      'artworkId': ?normalizedArtworkId,
      'message': ?normalizedMessage,
      'fiat': ?fiatSnapshot?.toPayload(),
    };
  }

  static PaymentLinkPresentation? fromPayload(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw const FormatException('Payment link presentation is invalid.');
    }
    final artworkId = _readOptionalString(value, 'artworkId');
    final message = _readOptionalString(value, 'message');
    final fiatSnapshot = PaymentLinkFiatSnapshot.fromPayload(value['fiat']);
    _validate(artworkId: artworkId, message: message);
    if (artworkId == null && message == null && fiatSnapshot == null) {
      return null;
    }
    return PaymentLinkPresentation(
      artworkId: artworkId,
      message: message,
      fiatSnapshot: fiatSnapshot,
    );
  }

  static void _validate({String? artworkId, String? message}) {
    if (artworkId != null &&
        !RegExp(
          '^[a-zA-Z0-9_-]{1,$maxArtworkIdLength}\$',
        ).hasMatch(artworkId)) {
      throw const FormatException('Payment link artwork is invalid.');
    }
    if (message != null) {
      if (message.characters.length > maxMessageCharacters) {
        throw const FormatException('Payment link message is too long.');
      }
      if (!isMessageWithinUtf8ByteLimit(message)) {
        throw const FormatException('Payment link message is too large.');
      }
    }
  }

  static String? _readOptionalString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('Payment link presentation "$key" is invalid.');
    }
    return _normalizeOptionalString(value);
  }

  static String? _normalizeOptionalString(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class VizorPaymentLink {
  const VizorPaymentLink({
    required this.network,
    required String address,
    required this.amountZatoshi,
    required this.mnemonic,
    required this.birthdayHeight,
    required this.label,
    required DateTime createdAt,
    this.presentation,
    this.isCreatedAtProvisional = false,
  }) : _address = address,
       _createdAt = createdAt;

  const VizorPaymentLink._parsed({
    required this.network,
    required String? address,
    required this.amountZatoshi,
    required this.mnemonic,
    required this.birthdayHeight,
    required this.label,
    required DateTime? createdAt,
    required this.presentation,
    this.isCreatedAtProvisional = false,
  }) : _address = address,
       _createdAt = createdAt;

  static const maxEncodedLength = 16 * 1024;
  static const _version = 2;
  static const _fragmentPrefix = 'v2=';
  static const _legacyVersion = 1;
  static const _legacyFragmentPrefix = 'v1=';

  final String network;
  final String? _address;
  final BigInt amountZatoshi;
  final String mnemonic;
  final int birthdayHeight;
  final String label;
  final DateTime? _createdAt;

  /// Local-only provenance; never included in the shared payload.
  final bool isCreatedAtProvisional;
  final PaymentLinkPresentation? presentation;

  /// The address derived from [mnemonic], when it is known locally.
  ///
  /// Versions 2 and 3 do not carry this value. A received link gains it when its
  /// temporary claim wallet imports the mnemonic.
  String get address =>
      _address ??
      (throw StateError('Payment link address has not been derived yet.'));

  /// The card creation time, when it is known locally or from the chain.
  ///
  /// Versions 2 and 3 do not carry this value. A received link gains it from the
  /// funding transaction's block time after its claim wallet syncs.
  DateTime get createdAt =>
      _createdAt ??
      (throw StateError('Payment link creation time is not known yet.'));

  /// Returns the locally known address without requiring it to be resolved.
  String? get knownAddress => _address;

  /// Returns the locally known creation time without requiring chain data.
  DateTime? get knownCreatedAt => _createdAt;

  /// Adds metadata derived while opening or syncing the claim wallet.
  VizorPaymentLink withResolvedMetadata({
    String? address,
    DateTime? createdAt,
    bool? isCreatedAtProvisional,
  }) {
    return VizorPaymentLink._parsed(
      network: network,
      address: address ?? _address,
      amountZatoshi: amountZatoshi,
      mnemonic: mnemonic,
      birthdayHeight: birthdayHeight,
      label: label,
      createdAt: createdAt ?? _createdAt,
      isCreatedAtProvisional:
          isCreatedAtProvisional ?? this.isCreatedAtProvisional,
      presentation: presentation,
    );
  }

  static bool supportsNetwork(String network) {
    final normalizedNetwork = network.trim();
    return normalizedNetwork == 'main' ||
        (kPaymentLinkRegtestEnabled && normalizedNetwork == 'regtest');
  }

  /// Compares every field carried by the versioned payment-link payload after
  /// applying the same normalization as [toUri]. This is intentionally stricter
  /// than claim-wallet cache identity: a corrected amount or changed
  /// presentation must remain a distinct intake item.
  bool hasSameCanonicalPayload(VizorPaymentLink other) {
    return _encodedPayload() == other._encodedPayload();
  }

  /// The established v2 representation. Prefer the purpose-specific methods
  /// below for sharing or persistence.
  Uri toUri() => toRecoveryUri();

  /// Stable local serialization, independent of the selected share writer.
  /// Resolved address, time, and submission evidence live in the enclosing record.
  Uri toRecoveryUri() => _uri('$_fragmentPrefix${_encodedPayload()}');

  /// Serialize for sharing. Callers dropping a known address must first verify
  /// it asynchronously with [rust_wallet.validateGiftAddress].
  Uri toShareUri() => _uri('v3=${_CompactPaymentLinkCodec.encode(this)}');

  /// Returns v2 only when legacy mnemonic whitespace cannot be carried by v3.
  /// The caller must first verify the original mnemonic against a known address.
  /// Canonicalization is used only to validate, never to replace the stored secret.
  Uri? toLegacyWhitespaceShareUri() {
    final original = mnemonic.trim();
    final canonical = original.split(RegExp(r'\s+')).join(' ');
    if (canonical == original) return null;
    if (knownAddress == null) {
      throw const FormatException('Gift card address could not be verified.');
    }
    // Apply every compact payload check as well, including BIP-39 validation.
    _uri('v3=${_CompactPaymentLinkCodec.encode(this, mnemonic: canonical)}');
    return toRecoveryUri();
  }

  static Uri _uri(String fragment) {
    final uri = Uri(
      scheme: VizorDeepLink.scheme,
      host: VizorDeepLink.host,
      path: VizorDeepLink.paymentLinkPath,
      fragment: fragment,
    );
    if (uri.toString().length > maxEncodedLength) {
      throw const FormatException('Payment link is too large.');
    }
    return uri;
  }

  String _encodedPayload() {
    final normalizedNetwork = network.trim();
    if (!supportsNetwork(normalizedNetwork)) {
      throw const FormatException(
        'Payment links are only available on mainnet.',
      );
    }
    final payload = <String, Object?>{
      'v': _version,
      'network': normalizedNetwork,
      'amountZatoshi': amountZatoshi.toString(),
      'mnemonic': mnemonic.trim(),
      'birthdayHeight': birthdayHeight,
      'label': label.trim(),
    };
    final presentationPayload = presentation?.toPayload();
    if (presentationPayload != null) {
      payload['presentation'] = presentationPayload;
    }
    return base64UrlEncode(utf8.encode(jsonEncode(payload)));
  }

  static bool matchesEndpoint(Uri uri) {
    return VizorDeepLink.routeFor(uri) == VizorDeepLinkRoute.paymentLink;
  }

  static VizorPaymentLink parse(String rawLink) {
    final trimmed = rawLink.trim();
    if (trimmed.length > maxEncodedLength) {
      throw const FormatException('Payment link is too large.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !matchesEndpoint(uri)) {
      throw const FormatException('This is not a Vizor payment link.');
    }
    if (uri.userInfo.isNotEmpty || uri.hasPort || uri.hasQuery) {
      throw const FormatException('Payment link URL is invalid.');
    }

    final fragment = uri.fragment;
    if (fragment.startsWith('v3=')) {
      return _CompactPaymentLinkCodec.decode(fragment.substring(3));
    }
    final int expectedVersion;
    final String fragmentPrefix;
    if (fragment.startsWith(_fragmentPrefix)) {
      expectedVersion = _version;
      fragmentPrefix = _fragmentPrefix;
    } else if (fragment.startsWith(_legacyFragmentPrefix)) {
      expectedVersion = _legacyVersion;
      fragmentPrefix = _legacyFragmentPrefix;
    } else {
      throw const FormatException('Payment link is missing its payload.');
    }
    final encoded = fragment.substring(fragmentPrefix.length);
    if (encoded.isEmpty || encoded.contains('&')) {
      throw const FormatException('Payment link payload is invalid.');
    }

    late final Object? decodedJson;
    try {
      decodedJson = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
    } catch (_) {
      throw const FormatException('Payment link payload could not be read.');
    }

    if (decodedJson is! Map<String, Object?>) {
      throw const FormatException('Payment link payload is invalid.');
    }
    final payload = decodedJson;
    if (payload['v'] != expectedVersion) {
      throw const FormatException('Payment link version is not supported.');
    }

    final network = _readString(payload, 'network');
    final amountZatoshi = _readBigInt(payload, 'amountZatoshi');
    final mnemonic = _readString(payload, 'mnemonic');
    final birthdayHeight = _readInt(payload, 'birthdayHeight');
    final label = _readString(payload, 'label');
    final address = expectedVersion == _legacyVersion
        ? _readString(payload, 'address')
        : null;
    final createdAtRaw = expectedVersion == _legacyVersion
        ? _readString(payload, 'createdAt')
        : null;
    final createdAt = createdAtRaw == null
        ? null
        : DateTime.tryParse(createdAtRaw);
    final presentation = PaymentLinkPresentation.fromPayload(
      payload['presentation'],
    );

    if (!supportsNetwork(network)) {
      throw const FormatException('Payment link network is not supported.');
    }
    if (address != null && address.isEmpty) {
      throw const FormatException('Payment link address is missing.');
    }
    if (amountZatoshi <= BigInt.zero) {
      throw const FormatException('Payment link amount is invalid.');
    }
    if (mnemonic.split(RegExp(r'\s+')).length < 12) {
      throw const FormatException('Payment link recovery phrase is invalid.');
    }
    if (birthdayHeight <= 0) {
      throw const FormatException('Payment link birthday height is invalid.');
    }
    if (createdAtRaw != null && createdAt == null) {
      throw const FormatException('Payment link timestamp is invalid.');
    }

    return VizorPaymentLink._parsed(
      network: network,
      address: address,
      amountZatoshi: amountZatoshi,
      mnemonic: mnemonic,
      birthdayHeight: birthdayHeight,
      label: label,
      createdAt: createdAt,
      presentation: presentation,
    );
  }

  static String _readString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String) {
      throw FormatException('Payment link is missing "$key".');
    }
    return value.trim();
  }

  static int _readInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    throw FormatException('Payment link "$key" is invalid.');
  }

  static BigInt _readBigInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is int) return BigInt.from(value);
    if (value is String) {
      final parsed = BigInt.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    throw FormatException('Payment link "$key" is invalid.');
  }
}
