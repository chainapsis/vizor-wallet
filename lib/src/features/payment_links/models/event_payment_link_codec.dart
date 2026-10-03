part of 'vizor_payment_link.dart';

/// Mainnet event links carry raw entropy and the full funding txid, once each.
/// The wire layout and permanent artwork codes are in docs/compact-gift-links.md.
abstract final class _EventPaymentLinkCodec {
  static const _messageFlag = 0x08;
  static const _reservedBits = 0xf0;

  // Wire codes are permanent: append new codes, never renumber or reuse them.
  // Zero means no specified artwork. Do not derive codes from a UI enum index.
  static const _artworks = <int, String>{
    1: 'knight',
    2: 'chestLava',
    3: 'chestCave',
    4: 'dragon',
    5: 'knightMagic',
    6: 'gandalf',
    7: 'crystal',
    8: 'diamond',
    9: 'ruby',
    10: 'coin',
    11: 'gift',
  };

  static FormatException get _invalid => _CompactPaymentLinkCodec._invalid;

  static String encode(VizorPaymentLink link) {
    try {
      // The network is implicit on the wire; never reinterpret a testnet card.
      if (link.network.trim() != 'main') throw _invalid;
      _CompactPaymentLinkCodec._validateRequired(
        'main',
        link.birthdayHeight,
        link.amountZatoshi,
      );
      final txid = VizorPaymentLink.validateFundingTxid(link.fundingTxid);
      final entropy = rust_wallet.giftMnemonicToEntropy(
        mnemonic: link.mnemonic.trim(),
      );
      final entropyCode = _CompactPaymentLinkCodec._entropyLengths.indexOf(
        entropy.length,
      );
      if (entropyCode < 0) throw _invalid;
      final presentation = link.presentation?.toPayload();
      final artwork = presentation?['artworkId'] as String?;
      final artworkCode = artwork == null
          ? 0
          : _artworks.entries.firstWhere((entry) => entry.value == artwork).key;
      final message = presentation?['message'] as String?;
      final header = entropyCode | (message == null ? 0 : _messageFlag);
      final numbers = ByteData(12)
        ..setUint32(0, link.birthdayHeight, Endian.big)
        ..setUint32(4, (link.amountZatoshi >> 32).toInt(), Endian.big)
        ..setUint32(
          8,
          (link.amountZatoshi & BigInt.from(0xffffffff)).toInt(),
          Endian.big,
        );
      final bytes = BytesBuilder(copy: false)
        ..addByte(header)
        ..add(entropy)
        ..add(numbers.buffer.asUint8List())
        // Txid bytes follow display-hex order. Rust converts protocol order.
        ..add(
          List.generate(
            32,
            (i) => int.parse(txid.substring(i * 2, i * 2 + 2), radix: 16),
          ),
        )
        ..addByte(artworkCode);
      if (message != null) _writeString(bytes, message);
      return _CompactPaymentLinkCodec._encodeBase64(bytes.takeBytes());
    } catch (_) {
      throw _invalid;
    }
  }

  static VizorPaymentLink decode(String encoded) {
    try {
      if (encoded.length > VizorPaymentLink.maxEncodedLength) throw _invalid;
      final bytes = _CompactPaymentLinkCodec._decodeBase64(encoded);
      final header = bytes[0];
      final entropyCode = header & 0x07;
      if (header & _reservedBits != 0 ||
          entropyCode >= _CompactPaymentLinkCodec._entropyLengths.length) {
        throw _invalid;
      }
      final entropyLength =
          _CompactPaymentLinkCodec._entropyLengths[entropyCode];
      final fixedLength = 1 + entropyLength + 4 + 8 + 32 + 1;
      if (bytes.length < fixedLength) throw _invalid;
      final numbers = ByteData.sublistView(bytes, 1 + entropyLength);
      final height = numbers.getUint32(0, Endian.big);
      final amount =
          (BigInt.from(numbers.getUint32(4, Endian.big)) << 32) |
          BigInt.from(numbers.getUint32(8, Endian.big));
      _CompactPaymentLinkCodec._validateRequired('main', height, amount);
      final txidStart = 1 + entropyLength + 12;
      final txid = bytes
          .sublist(txidStart, txidStart + 32)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final artworkCode = bytes[fixedLength - 1];
      if (artworkCode != 0 && !_artworks.containsKey(artworkCode)) {
        throw _invalid;
      }
      String? message;
      if (header & _messageFlag != 0) {
        if (bytes.length < fixedLength + 2) throw _invalid;
        final length = ByteData.sublistView(
          bytes,
          fixedLength,
        ).getUint16(0, Endian.big);
        if (length == 0 ||
            length > PaymentLinkPresentation.maxMessageUtf8Bytes ||
            bytes.length != fixedLength + 2 + length) {
          throw _invalid;
        }
        message = utf8.decode(bytes.sublist(fixedLength + 2));
        if (message != message.trim()) throw _invalid;
      } else if (bytes.length != fixedLength) {
        throw _invalid;
      }
      final presentation = PaymentLinkPresentation.fromPayload({
        'artworkId': _artworks[artworkCode],
        'message': message,
      });
      final mnemonic = rust_wallet.giftMnemonicFromEntropy(
        entropy: Uint8List.sublistView(bytes, 1, 1 + entropyLength),
      );
      final link = VizorPaymentLink._parsed(
        network: 'main',
        address: null,
        amountZatoshi: amount,
        mnemonic: mnemonic,
        birthdayHeight: height,
        label: _CompactPaymentLinkCodec._defaultLabel,
        createdAt: null,
        presentation: presentation,
        fundingTxid: txid,
      );
      // Shared cards must fit durable recovery storage before any claim work.
      link.toRecoveryUri();
      return link;
    } catch (_) {
      // Never include the secret-bearing input in an error.
      throw _invalid;
    }
  }

  static void _writeString(BytesBuilder bytes, String value) {
    final encoded = utf8.encode(value);
    if (encoded.length > 0xffff) throw _invalid;
    bytes
      ..add(
        (ByteData(
          2,
        )..setUint16(0, encoded.length, Endian.big)).buffer.asUint8List(),
      )
      ..add(encoded);
  }
}
