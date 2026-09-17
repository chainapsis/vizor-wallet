part of 'vizor_payment_link.dart';

/// Compact gift links use the positional JSON schema in docs/compact-gift-links.md.
/// Failures never include the secret-bearing input.
abstract final class _CompactPaymentLinkCodec {
  static const _entropyLengths = [16, 20, 24, 28, 32];
  static const _defaultLabel = 'Payment link';
  static final _maxAmount = BigInt.from(21000000) * BigInt.from(100000000);

  static FormatException get _invalid =>
      const FormatException('Gift link payload is invalid or unsupported.');

  static String encode(VizorPaymentLink link) {
    try {
      final network = link.network.trim();
      _validateRequired(network, link.birthdayHeight, link.amountZatoshi);
      final presentation = link.presentation?.toPayload();
      final entropy = rust_wallet.giftMnemonicToEntropy(
        mnemonic: link.mnemonic.trim(),
      );
      if (!_entropyLengths.contains(entropy.length)) throw _invalid;
      final label = link.label.trim();
      final payload = <Object?>[
        network,
        _encodeBase64(entropy),
        link.birthdayHeight,
        link.amountZatoshi.toString(),
        presentation?['artworkId'],
        link.presentation?.fiatSnapshot?.amount,
        presentation?['message'],
        label == _defaultLabel ? null : label,
      ];
      while (payload.length > 4 && payload.last == null) {
        payload.removeLast();
      }
      return _encodeBase64(utf8.encode(jsonEncode(payload)));
    } catch (_) {
      throw _invalid;
    }
  }

  static VizorPaymentLink decode(String encoded) {
    try {
      if (encoded.length > VizorPaymentLink.maxEncodedLength) throw _invalid;
      final payload = jsonDecode(utf8.decode(_decodeBase64(encoded)));
      if (payload is! List<Object?> ||
          payload.length < 4 ||
          payload.length > 8) {
        throw _invalid;
      }
      final network = payload[0];
      final encodedEntropy = payload[1];
      final height = payload[2];
      final amountText = payload[3];
      if (network is! String ||
          encodedEntropy is! String ||
          encodedEntropy.length > 43 ||
          height is! int ||
          amountText is! String ||
          !RegExp(r'^[1-9][0-9]*$').hasMatch(amountText)) {
        throw _invalid;
      }
      final amount = BigInt.parse(amountText);
      _validateRequired(network.trim(), height, amount);
      final entropy = _decodeBase64(encodedEntropy);
      if (!_entropyLengths.contains(entropy.length)) throw _invalid;
      final artwork = payload.length > 4 ? payload[4] : null;
      final fiat = payload.length > 5 ? payload[5] : null;
      final message = payload.length > 6 ? payload[6] : null;
      final label = payload.length > 7 ? payload[7] : null;
      if (label != null && label is! String) throw _invalid;
      final presentation = PaymentLinkPresentation.fromPayload({
        'artworkId': artwork,
        'message': message,
        'fiat': fiat == null ? null : {'amount': fiat, 'currency': 'USD'},
      });
      final mnemonic = rust_wallet.giftMnemonicFromEntropy(entropy: entropy);
      final link = VizorPaymentLink._parsed(
        network: network.trim(),
        address: null,
        amountZatoshi: amount,
        mnemonic: mnemonic,
        birthdayHeight: height,
        label: (label as String?)?.trim() ?? _defaultLabel,
        createdAt: null,
        presentation: presentation,
      );
      // Accepted gifts must fit the durable recovery format before claim.
      link.toRecoveryUri();
      return link;
    } catch (_) {
      throw _invalid;
    }
  }

  static void _validateRequired(String network, int height, BigInt amount) {
    if (!VizorPaymentLink.supportsNetwork(network) ||
        height <= 0 ||
        height > 0xffffffff ||
        amount <= BigInt.zero ||
        amount > _maxAmount) {
      throw _invalid;
    }
  }

  static String _encodeBase64(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Uint8List _decodeBase64(String encoded) {
    if (encoded.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
      throw _invalid;
    }
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (_encodeBase64(bytes) != encoded) throw _invalid;
    return bytes;
  }
}
