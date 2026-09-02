/// Builds the `zcash:` payment URIs this wallet hands out when someone
/// requests an amount from the Receive screen.
///
/// This is the write side of [Zip321PaymentRequest], which only parses. Every
/// URI produced here has to survive `Zip321PaymentRequest.parse` unchanged —
/// the round-trip is what makes a request link usable by the same wallet that
/// created it, and it is pinned by the unit tests.
///
/// Scope is deliberately narrow: one recipient, an amount, and an optional
/// text memo. `label` and `message` are never emitted. They would travel to
/// everyone the link is forwarded to, and the only value the wallet could put
/// in them is the local account name — a privacy leak with no payer benefit.
library;

import 'dart:convert';

/// ZIP-302 memo field size. A memo is rejected above this, not truncated:
/// silently cutting a message in half is worse than refusing it.
const kZip321MaxMemoBytes = 512;

/// Total ZEC supply, the ceiling ZIP-321 puts on an `amount` parameter.
const kZip321MaxAmountZec = 21000000;

/// Zatoshi per ZEC — the amount is normalized through integers so no
/// binary-float rounding can reach the emitted string.
const _zatoshiPerZec = 100000000;

/// Decimal places an `amount` parameter may carry.
const kZip321MaxAmountDecimals = 8;

/// Why [buildZip321PaymentUri] refused to build a URI.
///
/// The caller maps these onto its own copy: the same rejection reads as an
/// inline field error on the request form and as a thrown bug anywhere else.
enum Zip321BuildErrorKind {
  /// Address is empty or is not the base-alphanumeric shape ZIP-321 allows.
  address,

  /// Amount is empty, not a plain decimal number, or is zero.
  amountFormat,

  /// Amount carries more than [kZip321MaxAmountDecimals] decimal places.
  amountDecimals,

  /// Amount is above [kZip321MaxAmountZec].
  amountSupply,

  /// Memo is longer than [kZip321MaxMemoBytes] when UTF-8 encoded.
  memoTooLong,

  /// A memo was supplied for a transparent address, which cannot carry one.
  memoTransparent,
}

/// A refusal from [buildZip321PaymentUri], carrying the machine-readable
/// [kind] beside a plain sentence for logs.
class Zip321BuildException implements Exception {
  const Zip321BuildException(this.kind, this.message);

  final Zip321BuildErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// True when [address] belongs to the transparent pool.
///
/// Matches `Zip321PaymentRequest.parse`, which rejects a memo on any address
/// starting with `t`, so the builder refuses exactly what the parser refuses.
bool zip321AddressIsTransparent(String address) => address.startsWith('t');

/// Builds `zcash:<address>?amount=<decimal>[&memo=<base64url>]`.
///
/// [amountZec] is a plain decimal string as typed (`'0.50'`, `'1'`,
/// `'0.00010000'`); it is normalized to its shortest exact form, so `0.50`
/// becomes `0.5` and `1.00000000` becomes `1`. Exponent notation is not
/// accepted — it never appears in the amount field and would not round-trip.
///
/// [memoText] is omitted when null or blank. Otherwise it is UTF-8 encoded
/// and written as unpadded base64url, which is the only memo form ZIP-321
/// defines.
///
/// Throws [Zip321BuildException] rather than returning a partial URI: a
/// half-valid payment link is the one output nobody can use.
String buildZip321PaymentUri({
  required String address,
  required String amountZec,
  String? memoText,
}) {
  final recipient = address.trim();
  if (recipient.isEmpty || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(recipient)) {
    throw const Zip321BuildException(
      Zip321BuildErrorKind.address,
      'Payment address is not a valid Zcash address.',
    );
  }

  final amount = normalizeZip321Amount(amountZec);

  final buffer = StringBuffer('zcash:$recipient?amount=$amount');

  final memo = memoText;
  if (memo != null && memo.trim().isNotEmpty) {
    if (zip321AddressIsTransparent(recipient)) {
      throw const Zip321BuildException(
        Zip321BuildErrorKind.memoTransparent,
        'Transparent payments cannot carry a message.',
      );
    }
    buffer.write('&memo=${encodeZip321Memo(memo)}');
  }

  return buffer.toString();
}

/// Normalizes a typed ZEC amount to the shortest exact decimal ZIP-321
/// accepts, or throws [Zip321BuildException].
///
/// Exposed separately so a form can validate a keystroke without building a
/// whole URI, and so the tests can pin the trimming rules on their own.
String normalizeZip321Amount(String amountZec) {
  final raw = amountZec.trim();
  final match = RegExp(r'^([0-9]+)(?:\.([0-9]*))?$').firstMatch(raw);
  if (match == null) {
    throw const Zip321BuildException(
      Zip321BuildErrorKind.amountFormat,
      'Enter an amount as a plain decimal number.',
    );
  }

  final rawFraction = match.group(2) ?? '';
  if (rawFraction.length > kZip321MaxAmountDecimals) {
    throw const Zip321BuildException(
      Zip321BuildErrorKind.amountDecimals,
      'Enter up to $kZip321MaxAmountDecimals decimals.',
    );
  }

  // Integer arithmetic all the way: parsing to double first would let
  // 0.1 + 0.2 style error into a value someone is asked to pay.
  final zatoshi =
      BigInt.parse(match.group(1)!) * BigInt.from(_zatoshiPerZec) +
      BigInt.parse(rawFraction.padRight(kZip321MaxAmountDecimals, '0'));

  if (zatoshi == BigInt.zero) {
    throw const Zip321BuildException(
      Zip321BuildErrorKind.amountFormat,
      'Enter an amount greater than zero.',
    );
  }
  if (zatoshi >
      BigInt.from(kZip321MaxAmountZec) * BigInt.from(_zatoshiPerZec)) {
    throw const Zip321BuildException(
      Zip321BuildErrorKind.amountSupply,
      'Amount exceeds the ZEC supply.',
    );
  }

  final integerPart = (zatoshi ~/ BigInt.from(_zatoshiPerZec)).toString();
  final fractionPart = (zatoshi % BigInt.from(_zatoshiPerZec))
      .toString()
      .padLeft(kZip321MaxAmountDecimals, '0')
      .replaceFirst(RegExp(r'0+$'), '');

  return fractionPart.isEmpty ? integerPart : '$integerPart.$fractionPart';
}

/// UTF-8 encodes [memoText] as the unpadded base64url ZIP-321 specifies.
///
/// The limit is measured in bytes, not characters: one emoji is four bytes,
/// so a 512-character message can be four times over the protocol maximum.
String encodeZip321Memo(String memoText) {
  final bytes = utf8.encode(memoText);
  if (bytes.length > kZip321MaxMemoBytes) {
    throw const Zip321BuildException(
      Zip321BuildErrorKind.memoTooLong,
      'Message is longer than $kZip321MaxMemoBytes bytes.',
    );
  }
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// UTF-8 byte length of [memoText] — what the 512-byte counter shows.
int zip321MemoByteLength(String memoText) => utf8.encode(memoText).length;
