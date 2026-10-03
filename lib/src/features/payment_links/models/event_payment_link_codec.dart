part of 'vizor_payment_link.dart';

/// Mainnet event links carry raw entropy and the full funding txid, once each.
/// The wire layout is in docs/compact-gift-links.md.
abstract final class _EventPaymentLinkCodec {
  static const _entropyLength = 16;
  static const _fixedLength = _entropyLength + 8 + 32;

  static FormatException get _invalid => _CompactPaymentLinkCodec._invalid;

  static String encode(VizorPaymentLink link) {
    try {
      // The network is implicit on the wire; never reinterpret a testnet card.
      if (link.network.trim() != 'main') throw _invalid;
      _CompactPaymentLinkCodec._validateRequired(
        'main',
        link.claimBirthdayHeight,
        link.amountZatoshi,
      );
      final txid = VizorPaymentLink.validateFundingTxid(link.fundingTxid);
      final entropy = rust_wallet.giftMnemonicToEntropy(
        mnemonic: link.mnemonic.trim(),
      );
      if (entropy.length != _entropyLength) throw _invalid;
      final presentation = link.presentation?.toPayload();
      final message = presentation?['message'] as String?;
      final amount = ByteData(8)
        ..setUint32(0, (link.amountZatoshi >> 32).toInt(), Endian.big)
        ..setUint32(
          4,
          (link.amountZatoshi & BigInt.from(0xffffffff)).toInt(),
          Endian.big,
        );
      final bytes = BytesBuilder(copy: false)
        ..add(entropy)
        ..add(amount.buffer.asUint8List())
        // Txid bytes follow display-hex order. Rust converts protocol order.
        ..add(
          List.generate(
            32,
            (i) => int.parse(txid.substring(i * 2, i * 2 + 2), radix: 16),
          ),
        );
      if (message != null) bytes.add(utf8.encode(message));
      return _CompactPaymentLinkCodec._encodeBase64(bytes.takeBytes());
    } catch (_) {
      throw _invalid;
    }
  }

  static VizorPaymentLink decode(String encoded) {
    try {
      if (encoded.length > VizorPaymentLink.maxEncodedLength) throw _invalid;
      final bytes = _CompactPaymentLinkCodec._decodeBase64(encoded);
      if (bytes.length < _fixedLength ||
          bytes.length >
              _fixedLength + PaymentLinkPresentation.maxMessageUtf8Bytes) {
        throw _invalid;
      }
      final numbers = ByteData.sublistView(bytes, _entropyLength);
      final amount =
          (BigInt.from(numbers.getUint32(0, Endian.big)) << 32) |
          BigInt.from(numbers.getUint32(4, Endian.big));
      final height = ZcashNetwork.mainnet.saplingActivationHeight;
      _CompactPaymentLinkCodec._validateRequired('main', height, amount);
      const txidStart = _entropyLength + 8;
      final txid = bytes
          .sublist(txidStart, txidStart + 32)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      String? message;
      if (bytes.length > _fixedLength) {
        message = utf8.decode(bytes.sublist(_fixedLength));
        if (message.trim().isEmpty || message != message.trim()) throw _invalid;
      }
      final presentation = PaymentLinkPresentation.fromPayload({
        'artworkId': 'gift',
        'message': message,
      });
      final mnemonic = rust_wallet.giftMnemonicFromEntropy(
        entropy: Uint8List.sublistView(bytes, 0, _entropyLength),
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
}
