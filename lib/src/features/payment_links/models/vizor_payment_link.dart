import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';

import '../../../core/config/network_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/navigation/vizor_deep_link.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;

part 'compact_payment_link_codec.dart';
part 'v4_payment_link_codec.dart';

enum PaymentLinkLocatorKind { birthday, fundingHeight, fundingTxid }

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
  VizorPaymentLink({
    required this.network,
    required String address,
    required this.amountZatoshi,
    required this.mnemonic,
    required this.birthdayHeight,
    required this.label,
    required DateTime createdAt,
    this.presentation,
    this.fundingHeight,
    this.fundingTxid,
    this.isCreatedAtProvisional = false,
  }) : _address = address,
       _messageInFundingMemo = true,
       _createdAt = createdAt {
    _rejectMultipleFundingLocators(fundingHeight, fundingTxid);
  }

  VizorPaymentLink._parsed({
    required this.network,
    required String? address,
    required this.amountZatoshi,
    required this.mnemonic,
    required this.birthdayHeight,
    required this.label,
    required DateTime? createdAt,
    required this.presentation,
    this.fundingHeight,
    this.fundingTxid,
    this.isCreatedAtProvisional = false,
    bool messageInFundingMemo = false,
  }) : _address = address,
       _messageInFundingMemo = messageInFundingMemo,
       _createdAt = createdAt {
    _rejectMultipleFundingLocators(fundingHeight, fundingTxid);
  }

  static const maxEncodedLength = 16 * 1024;
  static const _version = 2;
  static const _fragmentPrefix = 'v2=';
  static const _legacyVersion = 1;
  static const _legacyFragmentPrefix = 'v1=';

  final String network;
  final String? _address;
  // New funding paths write the message into the transaction. Imported URL
  // messages must remain in their share payload until that is known to be true.
  final bool _messageInFundingMemo;
  final BigInt amountZatoshi;
  final String mnemonic;
  final int birthdayHeight;
  final String label;
  final DateTime? _createdAt;

  /// The funding block used for bounded discovery instead of a history scan.
  final int? fundingHeight;

  /// The single funding transaction used for direct claim.
  final String? fundingTxid;

  PaymentLinkLocatorKind get locatorKind => fundingTxid != null
      ? PaymentLinkLocatorKind.fundingTxid
      : fundingHeight != null
      ? PaymentLinkLocatorKind.fundingHeight
      : PaymentLinkLocatorKind.birthday;

  bool get isDirectClaim => locatorKind != PaymentLinkLocatorKind.birthday;

  /// Direct-only card wallets use a stable local birthday, absent from v4.
  /// Keeping it at activation also permits funding to move earlier in a reorg.
  int get claimBirthdayHeight => isDirectClaim
      ? zcashNetworkFromName(network).saplingActivationHeight
      : birthdayHeight;

  /// Local-only provenance; never included in the shared payload.
  final bool isCreatedAtProvisional;
  final PaymentLinkPresentation? presentation;

  /// The address derived from [mnemonic], when it is known locally.
  ///
  /// Versions 2 through 4 do not carry this value. A received link gains it
  /// when its temporary claim wallet imports the mnemonic.
  String get address =>
      _address ??
      (throw StateError('Payment link address has not been derived yet.'));

  /// The card creation time, when it is known locally or from the chain.
  ///
  /// Versions 2 through 4 do not carry this value. A received link gains it
  /// from the funding transaction's block time after its claim wallet syncs.
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
      messageInFundingMemo: _messageInFundingMemo,
      fundingHeight: fundingHeight,
      fundingTxid: fundingTxid,
    );
  }

  static void _rejectMultipleFundingLocators(
    int? fundingHeight,
    String? fundingTxid,
  ) {
    if (fundingHeight != null && fundingTxid != null) {
      throw ArgumentError(
        'A Gift Card cannot use both a funding height and funding transaction.',
      );
    }
  }

  static int validateFundingHeight(Object? value) {
    if (value is! int || value <= 0 || value > 0xffffffff) {
      throw const FormatException('Gift card funding height is invalid.');
    }
    return value;
  }

  static String validateFundingTxid(Object? value) {
    if (value is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw const FormatException('Gift card funding transaction is invalid.');
    }
    return value.toLowerCase();
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
  Uri toRecoveryUri() => _uri(
    '$_fragmentPrefix${_encodedPayload(includeMessageSource: true)}',
    path: VizorDeepLink.paymentLinkPath,
  );

  /// Serialize for sharing. Callers dropping a known address must first verify
  /// it asynchronously with [rust_wallet.validateGiftAddress].
  Uri toShareUri() {
    final words = mnemonic.trim().split(RegExp(r'\s+')).length;
    if (locatorKind == PaymentLinkLocatorKind.birthday &&
        (words != 12 ||
            network.trim() != 'main' ||
            (presentation?.message != null && !_messageInFundingMemo))) {
      return _uri(
        'v3=${_CompactPaymentLinkCodec.encode(this)}',
        path: VizorDeepLink.paymentLinkPath,
      );
    }
    return _uri(
      'v4=${_V4PaymentLinkCodec.encode(this)}',
      path: VizorDeepLink.giftPath,
    );
  }

  /// Encodes an externally funded v4 card without initializing the Rust bridge.
  ///
  /// The entropy is the original 16-byte BIP-39 entropy. External issuers can
  /// use this after funding a card and learning its confirmed height or txid.
  static Uri encodeV4FromEntropy({
    required List<int> entropy,
    required BigInt amountZatoshi,
    required PaymentLinkLocatorKind locatorKind,
    int? birthdayHeight,
    int? fundingHeight,
    String? fundingTxid,
    PaymentLinkPresentation? presentation,
  }) => _uri(
    'v4=${_V4PaymentLinkCodec.encodeFields(entropy: entropy, amountZatoshi: amountZatoshi, locatorKind: locatorKind, birthdayHeight: birthdayHeight, fundingHeight: fundingHeight, fundingTxid: fundingTxid, presentation: presentation)}',
    path: VizorDeepLink.giftPath,
  );

  /// Returns v2 for ordinary cards whose legacy whitespace cannot fit v3.
  /// The caller must first verify the original mnemonic against a known address.
  /// Canonicalization is used only to validate, never to replace the stored secret.
  Uri? toLegacyWhitespaceShareUri() {
    final original = mnemonic.trim();
    final canonical = original.split(RegExp(r'\s+')).join(' ');
    if (canonical == original) return null;
    if (isDirectClaim) {
      throw const FormatException(
        'Event gift cards require a standard secret passphrase.',
      );
    }
    if (knownAddress == null) {
      throw const FormatException('Gift card address could not be verified.');
    }
    // Apply every compact payload check as well, including BIP-39 validation.
    _uri(
      'v3=${_CompactPaymentLinkCodec.encode(this, mnemonic: canonical)}',
      path: VizorDeepLink.paymentLinkPath,
    );
    return toRecoveryUri();
  }

  static Uri _uri(String fragment, {required String path}) {
    final uri = Uri(
      scheme: VizorDeepLink.scheme,
      host: VizorDeepLink.host,
      path: path,
      fragment: fragment,
    );
    if (uri.toString().length > maxEncodedLength) {
      throw const FormatException('Payment link is too large.');
    }
    return uri;
  }

  String _encodedPayload({bool includeMessageSource = false}) {
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
      'birthdayHeight': claimBirthdayHeight,
      'label': label.trim(),
      if (fundingHeight != null)
        'fundingHeight': validateFundingHeight(fundingHeight),
      if (fundingTxid != null) 'fundingTxid': validateFundingTxid(fundingTxid),
    };
    final presentationPayload = presentation?.toPayload();
    if (presentationPayload != null) {
      payload['presentation'] = presentationPayload;
      if (includeMessageSource &&
          presentationPayload['message'] != null &&
          _messageInFundingMemo &&
          mnemonic.trim().split(RegExp(r'\s+')).length == 12 &&
          network.trim() == 'main') {
        payload['messageInFundingMemo'] = true;
      }
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
    if (fragment.startsWith('v4=')) {
      return _V4PaymentLinkCodec.decode(fragment.substring(3));
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

    final fundingTxid = payload.containsKey('fundingTxid')
        ? validateFundingTxid(payload['fundingTxid'])
        : null;
    final fundingHeight = payload.containsKey('fundingHeight')
        ? validateFundingHeight(payload['fundingHeight'])
        : null;
    if (fundingHeight != null && fundingTxid != null) {
      throw const FormatException(
        'A Gift Card cannot use both a funding height and funding transaction.',
      );
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
      messageInFundingMemo: payload['messageInFundingMemo'] == true,
      fundingHeight: fundingHeight,
      fundingTxid: fundingTxid,
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
