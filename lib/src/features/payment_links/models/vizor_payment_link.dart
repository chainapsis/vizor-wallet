import 'dart:convert';

import 'package:characters/characters.dart';

class PaymentLinkPresentation {
  const PaymentLinkPresentation({this.artworkId, this.message});

  static const maxArtworkIdLength = 64;
  static const maxMessageCharacters = 128;
  static const maxMessageUtf8Bytes = 512;

  final String? artworkId;
  final String? message;

  static bool isMessageWithinUtf8ByteLimit(String? message) {
    final normalizedMessage = _normalizeOptionalString(message);
    return normalizedMessage == null ||
        utf8.encode(normalizedMessage).length <= maxMessageUtf8Bytes;
  }

  Map<String, Object?>? toPayload() {
    final normalizedArtworkId = _normalizeOptionalString(artworkId);
    final normalizedMessage = _normalizeOptionalString(message);
    _validate(artworkId: normalizedArtworkId, message: normalizedMessage);
    if (normalizedArtworkId == null && normalizedMessage == null) {
      return null;
    }
    return <String, Object?>{
      'artworkId': ?normalizedArtworkId,
      'message': ?normalizedMessage,
    };
  }

  static PaymentLinkPresentation? fromPayload(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw const FormatException('Payment link presentation is invalid.');
    }
    final artworkId = _readOptionalString(value, 'artworkId');
    final message = _readOptionalString(value, 'message');
    _validate(artworkId: artworkId, message: message);
    if (artworkId == null && message == null) return null;
    return PaymentLinkPresentation(artworkId: artworkId, message: message);
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
    required this.address,
    required this.amountZatoshi,
    required this.mnemonic,
    required this.birthdayHeight,
    required this.label,
    required this.createdAt,
    this.presentation,
  });

  static const scheme = 'https';
  static const host = 'functions.vizor.cash';
  static const path = '/payment-links/open';
  static const maxEncodedLength = 16 * 1024;
  static const _version = 1;
  static const _fragmentPrefix = 'v1=';

  final String network;
  final String address;
  final BigInt amountZatoshi;
  final String mnemonic;
  final int birthdayHeight;
  final String label;
  final DateTime createdAt;
  final PaymentLinkPresentation? presentation;

  static bool supportsNetwork(String network) => network.trim() == 'main';

  /// Compares every field carried by the versioned payment-link payload after
  /// applying the same normalization as [toUri]. This is intentionally stricter
  /// than claim-wallet cache identity: a corrected amount or changed
  /// presentation must remain a distinct intake item.
  bool hasSameCanonicalPayload(VizorPaymentLink other) {
    return _encodedPayload() == other._encodedPayload();
  }

  Uri toUri() {
    return Uri(
      scheme: scheme,
      host: host,
      path: path,
      fragment: '$_fragmentPrefix${_encodedPayload()}',
    );
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
      'address': address.trim(),
      'amountZatoshi': amountZatoshi.toString(),
      'mnemonic': mnemonic.trim(),
      'birthdayHeight': birthdayHeight,
      'label': label.trim(),
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
    final presentationPayload = presentation?.toPayload();
    if (presentationPayload != null) {
      payload['presentation'] = presentationPayload;
    }
    return base64UrlEncode(utf8.encode(jsonEncode(payload)));
  }

  static bool matchesEndpoint(Uri uri) {
    return uri.scheme.toLowerCase() == scheme &&
        uri.host.toLowerCase() == host &&
        uri.path == path;
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
    if (!fragment.startsWith(_fragmentPrefix)) {
      throw const FormatException('Payment link is missing its payload.');
    }
    final encoded = fragment.substring(_fragmentPrefix.length);
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
    if (payload['v'] != _version) {
      throw const FormatException('Payment link version is not supported.');
    }

    final network = _readString(payload, 'network');
    final address = _readString(payload, 'address');
    final amountZatoshi = _readBigInt(payload, 'amountZatoshi');
    final mnemonic = _readString(payload, 'mnemonic');
    final birthdayHeight = _readInt(payload, 'birthdayHeight');
    final label = _readString(payload, 'label');
    final createdAtRaw = _readString(payload, 'createdAt');
    final createdAt = DateTime.tryParse(createdAtRaw);
    final presentation = PaymentLinkPresentation.fromPayload(
      payload['presentation'],
    );

    if (!supportsNetwork(network)) {
      throw const FormatException('Payment link network is not supported.');
    }
    if (address.isEmpty) {
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
    if (createdAt == null) {
      throw const FormatException('Payment link timestamp is invalid.');
    }

    return VizorPaymentLink(
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
