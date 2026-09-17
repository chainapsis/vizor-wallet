part of 'vizor_payment_link.dart';

/// The v3 wire contract is specified in docs/compact-gift-links.md.
/// All failures are deliberately independent of the secret-bearing input.
abstract final class _CompactPaymentLinkCodec {
  static const _entropyLengths = [16, 20, 24, 28, 32];
  static const _defaultLabel = 'Payment link';
  static final _checksumDomain = utf8.encode('VizorPaymentLink/v3\u0000');

  // Permanent assignments. Never derive these from picker or enum order.
  static const _artwork = <int, String>{
    1: 'knightMagic',
    2: 'knight',
    3: 'chestLava',
    4: 'chestCave',
    5: 'dragon',
    6: 'gandalf',
    7: 'crystal',
    8: 'diamond',
    9: 'ruby',
    10: 'coin',
    11: 'gift',
  };
  static final _maxAmount = BigInt.from(21000000) * BigInt.from(100000000);

  static FormatException get _invalid =>
      const FormatException('Gift link payload is invalid or unsupported.');

  static String encode(VizorPaymentLink link) {
    try {
      final network = link.network.trim();
      if (!VizorPaymentLink.supportsNetwork(network) ||
          link.birthdayHeight <= 0 ||
          link.birthdayHeight > 0xffffffff ||
          link.amountZatoshi <= BigInt.zero ||
          link.amountZatoshi > _maxAmount) {
        throw _invalid;
      }
      final presentation = link.presentation?.toPayload();
      final artwork = presentation?['artworkId'] as String?;
      final message = presentation?['message'] as String?;
      final fiat = link.presentation?.fiatSnapshot;
      final label = link.label.trim();
      final entropy = rust_wallet.giftMnemonicToEntropy(
        mnemonic: link.mnemonic.trim(),
      );
      final entropyCode = _entropyLengths.indexOf(entropy.length);
      if (entropyCode < 0) throw _invalid;
      final bytes = BytesBuilder(copy: false);
      bytes.addByte((entropyCode << 2) | (network == 'main' ? 0 : 2));
      bytes.addByte(
        (artwork == null ? 0 : 1) |
            (fiat == null ? 0 : 2) |
            (message == null ? 0 : 4) |
            (label == _defaultLabel ? 0 : 8),
      );
      bytes.add(entropy);
      final required = ByteData(12)
        ..setUint32(0, link.birthdayHeight, Endian.little)
        ..setUint64(4, link.amountZatoshi.toInt(), Endian.little);
      bytes.add(required.buffer.asUint8List());
      if (artwork != null) {
        final code = _artwork.entries
            .where((entry) => entry.value == artwork)
            .firstOrNull
            ?.key;
        bytes.addByte(code ?? 255);
        if (code == null) {
          final text = utf8.encode(artwork);
          bytes.addByte(text.length);
          bytes.add(text);
        }
      }
      if (fiat != null) {
        final value = ByteData(8)..setFloat64(0, fiat.amount, Endian.little);
        bytes.add(value.buffer.asUint8List());
      }
      if (message != null) _writeText(bytes, message);
      if (label != _defaultLabel) _writeText(bytes, label);
      final body = bytes.takeBytes();
      final payload = Uint8List.fromList([...body, ..._checksum(body)]);
      return base64UrlEncode(payload).replaceAll('=', '');
    } catch (_) {
      throw _invalid;
    }
  }

  static VizorPaymentLink decode(String encoded) {
    try {
      if (encoded.isEmpty ||
          encoded.length > VizorPaymentLink.maxEncodedLength ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
        throw _invalid;
      }
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      if (base64UrlEncode(bytes).replaceAll('=', '') != encoded ||
          bytes.length < 34) {
        throw _invalid;
      }
      final body = Uint8List.sublistView(bytes, 0, bytes.length - 4);
      final checksum = _checksum(body);
      for (var i = 0; i < 4; i++) {
        if (checksum[i] != bytes[body.length + i]) throw _invalid;
      }
      final reader = _CompactLinkReader(body);
      final header = reader.byte();
      final entropyCode = (header >> 2) & 7;
      final networkCode = header & 3;
      if (header >> 5 != 0 ||
          entropyCode >= _entropyLengths.length ||
          (networkCode != 0 && networkCode != 2)) {
        throw _invalid;
      }
      final network = networkCode == 0 ? 'main' : 'regtest';
      if (!VizorPaymentLink.supportsNetwork(network)) throw _invalid;
      final flags = reader.byte();
      if (flags & ~15 != 0) throw _invalid;
      final entropy = reader.take(_entropyLengths[entropyCode]);
      final height = reader.data(4).getUint32(0, Endian.little);
      final amountBytes = reader.take(8);
      var amount = BigInt.zero;
      for (var i = 7; i >= 0; i--) {
        amount = (amount << 8) | BigInt.from(amountBytes[i]);
      }
      if (height == 0 || amount <= BigInt.zero || amount > _maxAmount) {
        throw _invalid;
      }
      String? artwork;
      if (flags & 1 != 0) {
        final code = reader.byte();
        artwork = code == 255
            ? utf8.decode(reader.take(reader.byte()))
            : _artwork[code];
        if (artwork == null ||
            artwork.isEmpty ||
            artwork != artwork.trim() ||
            (code == 255 && _artwork.containsValue(artwork))) {
          throw _invalid;
        }
      }
      PaymentLinkFiatSnapshot? fiat;
      if (flags & 2 != 0) {
        final value = reader.data(8).getFloat64(0, Endian.little);
        if (value < 0 || !value.isFinite) throw _invalid;
        fiat = PaymentLinkFiatSnapshot(amount: value);
      }
      final message = flags & 4 == 0
          ? null
          : reader.text(PaymentLinkPresentation.maxMessageUtf8Bytes);
      final label = flags & 8 == 0 ? _defaultLabel : reader.text(0xffff);
      if (!reader.atEnd ||
          message != message?.trim() ||
          message == '' ||
          label != label.trim() ||
          (flags & 8 != 0 && label == _defaultLabel)) {
        throw _invalid;
      }
      final presentation = PaymentLinkPresentation.fromPayload({
        'artworkId': ?artwork,
        'message': ?message,
        'fiat': ?fiat?.toPayload(),
      });
      // Only BIP-39 conversion crosses FFI. Address/seed derivation and chain
      // access stay in asynchronous funding and claim operations.
      final mnemonic = rust_wallet.giftMnemonicFromEntropy(entropy: entropy);
      final link = VizorPaymentLink._parsed(
        network: network,
        address: null,
        amountZatoshi: amount,
        mnemonic: mnemonic,
        birthdayHeight: height,
        label: label,
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

  static List<int> _checksum(List<int> body) =>
      sha256.convert([..._checksumDomain, ...body]).bytes.sublist(0, 4);

  static void _writeText(BytesBuilder output, String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > 0xffff || utf8.decode(bytes) != value) throw _invalid;
    output.add(
      (ByteData(
        2,
      )..setUint16(0, bytes.length, Endian.little)).buffer.asUint8List(),
    );
    output.add(bytes);
  }
}

class _CompactLinkReader {
  _CompactLinkReader(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  bool get atEnd => offset == bytes.length;
  Uint8List take(int length) {
    if (length < 0 || length > bytes.length - offset) {
      throw _CompactPaymentLinkCodec._invalid;
    }
    final result = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return result;
  }

  int byte() => take(1).single;
  ByteData data(int length) => ByteData.sublistView(take(length));
  String text(int maxLength) {
    final length = data(2).getUint16(0, Endian.little);
    if (length > maxLength) throw _CompactPaymentLinkCodec._invalid;
    return utf8.decode(take(length));
  }
}
