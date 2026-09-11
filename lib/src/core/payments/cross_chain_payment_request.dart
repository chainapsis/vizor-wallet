import 'dart:convert';

import '../navigation/payment_request_draft.dart';
import '../zcash/zip321_payment_request.dart'
    show stripUnsupportedZip321MemoText;

const crossChainPaymentSchemes = {'bitcoin', 'litecoin', 'ethereum', 'solana'};

bool isCrossChainPaymentUri(String value) {
  final separator = value.indexOf(':');
  return separator > 0 &&
      crossChainPaymentSchemes.contains(
        value.substring(0, separator).trim().toLowerCase(),
      );
}

class PaymentRequestNetwork {
  const PaymentRequestNetwork(this.chain, this.label, this.nativeSymbol);
  final String chain;
  final String label;
  final String nativeSymbol;
}

const evmPaymentNetworks = <String, PaymentRequestNetwork>{
  '1': PaymentRequestNetwork('eth', 'Ethereum', 'ETH'),
  '10': PaymentRequestNetwork('op', 'Optimism', 'ETH'),
  '56': PaymentRequestNetwork('bsc', 'BNB Chain', 'BNB'),
  '137': PaymentRequestNetwork('pol', 'Polygon', 'POL'),
  '196': PaymentRequestNetwork('xlayer', 'X Layer', 'OKB'),
  '8453': PaymentRequestNetwork('base', 'Base', 'ETH'),
  '42161': PaymentRequestNetwork('arb', 'Arbitrum', 'ETH'),
  '43114': PaymentRequestNetwork('avax', 'Avalanche', 'AVAX'),
};

class CrossChainPaymentRequest implements PaymentRequestDraft {
  const CrossChainPaymentRequest({
    required this.id,
    required this.rawUri,
    required this.address,
    required this.isEvm,
    this.chain,
    this.chainId,
    this.contractAddress,
    this.amount,
    this.label,
    this.message,
    this.unsupportedReason,
  });

  @override
  final String id;
  final String rawUri;
  final String address;
  final bool isEvm;
  final String? chain;
  final String? chainId;
  final String? contractAddress;
  final PaymentRequestAmount? amount;
  final String? label;
  final String? message;

  /// A syntactically valid request whose transaction conditions cannot be met.
  /// Keep it as a request so the UI can explain it without extracting an address.
  final String? unsupportedReason;

  bool get needsNetwork => isEvm && chainId == null;

  static CrossChainPaymentRequest fromParserJson({
    required String id,
    required String rawUri,
    required String json,
  }) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      if (data['version'] != 1) throw const FormatException();
      String text(String key) => data[key] as String;
      String? optional(String key) => data[key] as String?;
      final type = text('type');
      final isEvm = type.startsWith('ethereum_');
      String? chain;
      String address = '';
      String? contract;
      String? unsupported;
      PaymentRequestAmount? amount;
      switch (type) {
        case 'bitcoin' || 'litecoin':
          chain = type == 'bitcoin' ? 'btc' : 'ltc';
          address = text('address');
          if (data['network'] != 'mainnet') {
            unsupported =
                'This request uses a test network. Pay supports mainnet payments.';
          }
          amount = PaymentRequestAmount.display(optional('amount'));
        case 'ethereum_native' || 'ethereum_erc20':
          address = text('recipient_address');
          contract = type == 'ethereum_erc20'
              ? text('token_contract_address')
              : null;
          if (type == 'ethereum_erc20' && optional('value_hex') == null ||
              type == 'ethereum_native' &&
                  optional('token_contract_address') != null) {
            throw const FormatException();
          }
          if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
            unsupported =
                'This request uses a name instead of an address. Ask the sender for a full wallet address.';
          }
          if (contract != null &&
              !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(contract)) {
            unsupported =
                'This request uses a token contract name that Vizor cannot resolve. Ask the sender for the contract address.';
          }
          amount = PaymentRequestAmount.atomicHex(optional('value_hex'));
          if (optional('gas_limit_hex') != null ||
              optional('gas_price_hex') != null) {
            unsupported =
                'This request specifies transaction fees that Vizor cannot apply. Ask the sender for a transfer request without custom fees.';
          }
        case 'solana_transfer':
          chain = 'sol';
          address = text('recipient');
          contract = optional('spl_token');
          amount = PaymentRequestAmount.display(optional('amount'));
          final references = data['references'] as List<dynamic>;
          if (references.isNotEmpty || optional('memo') != null) {
            unsupported =
                'This request needs payment tracking details that Vizor cannot send yet. Use a Solana Pay wallet to complete it.';
          }
        case 'solana_transaction':
          chain = 'sol';
          unsupported =
              'This request needs a Solana transaction that Vizor cannot perform. Use a Solana Pay wallet to complete it.';
        case 'ethereum_unrecognised':
          unsupported =
              'This request calls a contract function. Vizor supports payment transfers only.';
        default:
          throw const FormatException();
      }
      return CrossChainPaymentRequest(
        id: id,
        rawUri: rawUri,
        address: address,
        isEvm: isEvm,
        chain: chain,
        chainId: optional('chain_id'),
        contractAddress: contract,
        amount: amount,
        label: optional('label') == null
            ? null
            : stripUnsupportedZip321MemoText(text('label')),
        message: optional('message') == null
            ? null
            : stripUnsupportedZip321MemoText(text('message')),
        unsupportedReason: unsupported,
      );
    } catch (_) {
      throw const CrossChainPaymentParseException();
    }
  }
}

class CrossChainPaymentParseException implements Exception {
  const CrossChainPaymentParseException();
  @override
  String toString() =>
      'This payment request is not valid. Ask the sender for a new one.';
}

/// Exact amount from the request; never passes through a binary floating point value.
class PaymentRequestAmount {
  const PaymentRequestAmount._(this.digits, this.scale, this.isAtomic);
  final BigInt digits;
  final int scale;
  final bool isAtomic;

  static PaymentRequestAmount? display(String? value) {
    if (value == null) return null;
    if (value.length > 256 || !RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
      throw const CrossChainPaymentParseException();
    }
    final parts = value.split('.');
    return PaymentRequestAmount._(
      BigInt.parse(parts.join()),
      parts.length == 2 ? parts[1].length : 0,
      false,
    );
  }

  static PaymentRequestAmount? atomicHex(String? value) {
    if (value == null) return null;
    if (!RegExp(r'^0x[0-9a-fA-F]{1,64}$').hasMatch(value)) {
      throw const CrossChainPaymentParseException();
    }
    return PaymentRequestAmount._(
      BigInt.parse(value.substring(2), radix: 16),
      0,
      true,
    );
  }

  String? forDecimals(int decimals) {
    if (decimals < 0 || decimals > 255) {
      throw const CrossChainPaymentParseException();
    }
    var units = digits;
    var places = isAtomic ? decimals : scale;
    if (!isAtomic && scale > decimals) {
      final divisor = BigInt.from(10).pow(scale - decimals);
      if (units.remainder(divisor) != BigInt.zero) {
        throw const CrossChainPaymentParseException();
      }
      units ~/= divisor;
      places = decimals;
    }
    if (units == BigInt.zero) return null;
    if (places == 0) return units.toString();
    final padded = units.toString().padLeft(places + 1, '0');
    final whole = padded.substring(0, padded.length - places);
    final fraction = padded
        .substring(padded.length - places)
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? whole : '$whole.$fraction';
  }
}
