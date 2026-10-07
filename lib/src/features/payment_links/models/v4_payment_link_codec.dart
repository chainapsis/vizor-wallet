part of 'vizor_payment_link.dart';

/// Version 4 binary gift-link codec. See docs/compact-gift-links.md.
abstract final class _V4PaymentLinkCodec {
  static const _entropyLength = 16;
  static const _maxDecodedLength = 1024;
  static const _birthdayMode = 0;
  static const _fundingHeightMode = 1;
  static const _fundingTxidMode = 2;
  static const _artworkTag = 1;
  static const _fiatTag = 2;

  static const _artworkIds = <String>[
    'knight',
    'chestLava',
    'chestCave',
    'dragon',
    'knightMagic',
    'gandalf',
    'crystal',
    'diamond',
    'ruby',
    'coin',
    'gift',
  ];

  static FormatException get _invalid => _CompactPaymentLinkCodec._invalid;

  static String encode(VizorPaymentLink link) {
    try {
      if (link.network.trim() != 'main') throw _invalid;
      return encodeFields(
        entropy: rust_wallet.giftMnemonicToEntropy(
          mnemonic: link.mnemonic.trim(),
        ),
        amountZatoshi: link.amountZatoshi,
        locatorKind: link.locatorKind,
        birthdayHeight: link.locatorKind == PaymentLinkLocatorKind.birthday
            ? link.birthdayHeight
            : null,
        fundingHeight: link.fundingHeight,
        fundingTxid: link.fundingTxid,
        presentation: link.presentation,
      );
    } catch (_) {
      throw _invalid;
    }
  }

  static String encodeFields({
    required List<int> entropy,
    required BigInt amountZatoshi,
    required PaymentLinkLocatorKind locatorKind,
    int? birthdayHeight,
    int? fundingHeight,
    String? fundingTxid,
    PaymentLinkPresentation? presentation,
  }) {
    try {
      if (entropy.length != _entropyLength ||
          entropy.any((byte) => byte < 0 || byte > 255)) {
        throw _invalid;
      }
      _CompactPaymentLinkCodec._validateRequired(
        'main',
        ZcashNetwork.mainnet.saplingActivationHeight,
        amountZatoshi,
      );
      if (amountZatoshi + BigInt.from(10000) >
          BigInt.from(21000000) * BigInt.from(100000000)) {
        throw _invalid;
      }
      final bytes = BytesBuilder(copy: false);
      switch (locatorKind) {
        case PaymentLinkLocatorKind.birthday:
          if (birthdayHeight == null ||
              fundingHeight != null ||
              fundingTxid != null) {
            throw _invalid;
          }
          bytes
            ..addByte(_birthdayMode)
            ..add(entropy)
            ..add(_encodeUleb128(amountZatoshi))
            ..add(_uint32(birthdayHeight));
        case PaymentLinkLocatorKind.fundingHeight:
          if (birthdayHeight != null || fundingTxid != null) throw _invalid;
          final height = VizorPaymentLink.validateFundingHeight(fundingHeight);
          bytes
            ..addByte(_fundingHeightMode)
            ..add(entropy)
            ..add(_encodeUleb128(amountZatoshi))
            ..add(_uint32(height));
        case PaymentLinkLocatorKind.fundingTxid:
          if (birthdayHeight != null || fundingHeight != null) throw _invalid;
          final txid = VizorPaymentLink.validateFundingTxid(fundingTxid);
          bytes
            ..addByte(_fundingTxidMode)
            ..add(entropy)
            ..add(_encodeUleb128(amountZatoshi))
            ..add(_hexBytes(txid));
      }

      final payload = presentation?.toPayload();
      final artworkId = payload?['artworkId'] as String?;
      final artworkIndex = artworkId == null
          ? -1
          : _artworkIds.indexOf(artworkId);
      if (artworkIndex >= 0) _addTlv(bytes, _artworkTag, [artworkIndex + 1]);
      final fiat = presentation?.fiatSnapshot;
      if (fiat != null) {
        fiat.toPayload();
        final data = ByteData(8)..setFloat64(0, fiat.amount, Endian.big);
        _addTlv(bytes, _fiatTag, data.buffer.asUint8List());
      }
      final result = bytes.takeBytes();
      if (result.length > _maxDecodedLength) throw _invalid;
      return _CompactPaymentLinkCodec._encodeBase64(result);
    } catch (_) {
      throw _invalid;
    }
  }

  static VizorPaymentLink decode(String encoded) {
    try {
      if (encoded.length > VizorPaymentLink.maxEncodedLength) throw _invalid;
      final bytes = _CompactPaymentLinkCodec._decodeBase64(encoded);
      if (bytes.length > _maxDecodedLength || bytes.length < 22) throw _invalid;
      var offset = 0;
      final mode = bytes[offset++];
      if (mode < _birthdayMode || mode > _fundingTxidMode) throw _invalid;
      final entropy = Uint8List.fromList(
        bytes.sublist(offset, offset + _entropyLength),
      );
      offset += _entropyLength;
      final amountResult = _decodeUleb128(bytes, offset);
      final amount = amountResult.value;
      offset = amountResult.nextOffset;
      _CompactPaymentLinkCodec._validateRequired(
        'main',
        ZcashNetwork.mainnet.saplingActivationHeight,
        amount,
      );
      if (amount + BigInt.from(10000) >
          BigInt.from(21000000) * BigInt.from(100000000)) {
        throw _invalid;
      }

      var birthdayHeight = ZcashNetwork.mainnet.saplingActivationHeight;
      int? fundingHeight;
      String? fundingTxid;
      if (mode == _fundingTxidMode) {
        if (offset + 32 > bytes.length) throw _invalid;
        fundingTxid = bytes
            .sublist(offset, offset + 32)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        offset += 32;
      } else {
        if (offset + 4 > bytes.length) throw _invalid;
        final height = ByteData.sublistView(
          bytes,
          offset,
          offset + 4,
        ).getUint32(0, Endian.big);
        if (height == 0) throw _invalid;
        offset += 4;
        if (mode == _birthdayMode) {
          birthdayHeight = height;
        } else {
          fundingHeight = height;
        }
      }

      String? artworkId;
      double? fiatAmount;
      final seenTags = <int>{};
      while (offset < bytes.length) {
        final tag = bytes[offset++];
        _UlebResult lengthResult;
        try {
          lengthResult = _decodeUleb128(bytes, offset);
        } catch (_) {
          break;
        }
        if (lengthResult.value > BigInt.from(bytes.length)) break;
        final length = lengthResult.value.toInt();
        offset = lengthResult.nextOffset;
        if (length > bytes.length - offset) break;
        final value = bytes.sublist(offset, offset + length);
        offset += length;
        if (!seenTags.add(tag) && (tag == _artworkTag || tag == _fiatTag)) {
          break;
        }
        try {
          switch (tag) {
            case _artworkTag:
              if (value.length != 1 ||
                  value.single == 0 ||
                  value.single > _artworkIds.length) {
                throw _invalid;
              }
              artworkId = _artworkIds[value.single - 1];
            case _fiatTag:
              if (value.length != 8) throw _invalid;
              final candidate = ByteData.sublistView(
                Uint8List.fromList(value),
              ).getFloat64(0, Endian.big);
              if (!candidate.isFinite || candidate < 0) throw _invalid;
              fiatAmount = candidate;
            default:
            // Unknown display options are length-delimited and skippable.
          }
        } catch (_) {
          break;
        }
      }

      final presentation = PaymentLinkPresentation.fromPayload({
        'artworkId': artworkId,
        'fiat': fiatAmount == null
            ? null
            : {'amount': fiatAmount, 'currency': 'USD'},
      });
      final link = VizorPaymentLink._parsed(
        network: 'main',
        address: null,
        amountZatoshi: amount,
        mnemonic: rust_wallet.giftMnemonicFromEntropy(entropy: entropy),
        birthdayHeight: birthdayHeight,
        label: _CompactPaymentLinkCodec._defaultLabel,
        createdAt: null,
        presentation: presentation,
        fundingHeight: fundingHeight,
        fundingTxid: fundingTxid,
      );
      link.toRecoveryUri();
      return link;
    } catch (_) {
      throw _invalid;
    }
  }

  static Uint8List _uint32(int value) {
    if (value <= 0 || value > 0xffffffff) throw _invalid;
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static List<int> _hexBytes(String hex) => List<int>.generate(
    32,
    (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
  );

  static void _addTlv(BytesBuilder target, int tag, List<int> value) {
    target
      ..addByte(tag)
      ..add(_encodeUleb128(BigInt.from(value.length)))
      ..add(value);
  }

  static Uint8List _encodeUleb128(BigInt value) {
    if (value < BigInt.zero) throw _invalid;
    final result = <int>[];
    do {
      var byte = (value & BigInt.from(0x7f)).toInt();
      value >>= 7;
      if (value != BigInt.zero) byte |= 0x80;
      result.add(byte);
    } while (value != BigInt.zero);
    return Uint8List.fromList(result);
  }

  static _UlebResult _decodeUleb128(Uint8List bytes, int offset) {
    final start = offset;
    var value = BigInt.zero;
    var shift = 0;
    while (offset < bytes.length && offset - start < 10) {
      final byte = bytes[offset++];
      value |= BigInt.from(byte & 0x7f) << shift;
      if (byte & 0x80 == 0) {
        if (_encodeUleb128(value).length != offset - start) throw _invalid;
        return _UlebResult(value, offset);
      }
      shift += 7;
    }
    throw _invalid;
  }
}

final class _UlebResult {
  const _UlebResult(this.value, this.nextOffset);
  final BigInt value;
  final int nextOffset;
}
