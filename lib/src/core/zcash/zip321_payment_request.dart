import 'dart:convert';

/// Upper bound on a `zcash:` payment URI we are willing to parse, in UTF-8
/// bytes. Matches `kMaxZcashUriBytes` in `windows/runner/utils.h`, which
/// measures the bytes it receives, so the native handoff and the Dart parser
/// refuse the same inputs — measuring UTF-16 code units here would let a URI
/// the native side rejects through, since one CJK character is one code unit
/// but three bytes.
const kMaxPaymentUriLength = 16384;

/// Longest attacker-controlled fragment we echo back into a user-facing parse
/// error. Anything longer is truncated so a hostile link cannot fill a
/// SnackBar with its own text.
const _maxEchoedNameLength = 32;

class Zip321PaymentRequest {
  const Zip321PaymentRequest({required this.payments, this.unsupportedReason});

  final List<Zip321Payment> payments;
  final String? unsupportedReason;

  bool get isSupported => unsupportedReason == null;

  Zip321Payment get primaryPayment => payments.first;

  static Zip321PaymentRequest parse(String input) {
    // Code units are never more than bytes, so the cheap check settles the
    // common case before the string is encoded.
    if (input.length > kMaxPaymentUriLength ||
        utf8.encode(input).length > kMaxPaymentUriLength) {
      throw const Zip321ParseException('Payment link is too long.');
    }
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const Zip321ParseException('Paste a zcash: payment URI.');
    }
    if (!trimmed.toLowerCase().startsWith('zcash:')) {
      throw const Zip321ParseException(
        'ZIP-321 requests must start with zcash:.',
      );
    }

    final body = trimmed.substring(trimmed.indexOf(':') + 1);
    if (body.startsWith('//')) {
      throw const Zip321ParseException('ZIP-321 URIs must not include //.');
    }

    final queryStart = body.indexOf('?');
    final addressPart = queryStart == -1 ? body : body.substring(0, queryStart);
    final query = queryStart == -1 ? '' : body.substring(queryStart + 1);

    final builders = <String, _Zip321PaymentBuilder>{};
    final seenKeys = <String>{};
    var hasCustomAsset = false;

    if (addressPart.isNotEmpty) {
      _validateAddress(addressPart);
      final builder = builders.putIfAbsent(
        '',
        () => _Zip321PaymentBuilder(index: ''),
      );
      builder.address = addressPart;
      seenKeys.add('address:');
    }

    if (query.isNotEmpty) {
      for (final rawParam in query.split('&')) {
        if (rawParam.isEmpty) continue;
        final separator = rawParam.indexOf('=');
        final rawName = separator == -1
            ? rawParam
            : rawParam.substring(0, separator);
        final rawValue = separator == -1
            ? ''
            : rawParam.substring(separator + 1);
        final parsedName = _parseParamName(rawName);
        final name = parsedName.name;
        final index = parsedName.index;
        final seenKey = '$name:$index';
        if (!_recognizedParamNames.contains(name)) {
          if (name.startsWith('req-')) {
            throw Zip321ParseException(
              'Required ZIP-321 parameter ${_echoSafe(name)} is not supported.',
            );
          }
          continue;
        }
        if (!seenKeys.add(seenKey)) {
          throw Zip321ParseException('Duplicate ${_echoSafe(name)} parameter.');
        }

        final builder = builders.putIfAbsent(
          index,
          () => _Zip321PaymentBuilder(index: index),
        );

        switch (name) {
          case 'address':
            _validateAddress(rawValue);
            builder.address = rawValue;
          case 'amount':
            _validateAmount(rawValue);
            builder.amount = rawValue;
          case 'label':
            builder.label = _decodeQChar(rawValue, 'label');
          case 'message':
            builder.message = _decodeQChar(rawValue, 'message');
          case 'memo':
            final memo = _parseMemo(rawValue);
            builder.memo = rawValue;
            builder.memoText = memo.text;
            builder.memoIsBinary = memo.isBinary;
          case 'req-asset':
            _validateBase64Url(rawValue, 'req-asset');
            builder.reqAsset = rawValue;
            hasCustomAsset = true;
        }
      }
    }

    if (builders.isEmpty) {
      throw const Zip321ParseException(
        'ZIP-321 request has no payment address.',
      );
    }

    final payments = builders.entries.toList()
      ..sort(
        (a, b) => _indexSortValue(a.key).compareTo(_indexSortValue(b.key)),
      );
    final parsedPayments = <Zip321Payment>[];
    for (final entry in payments) {
      final builder = entry.value;
      if (builder.address == null) {
        throw const Zip321ParseException(
          'Each ZIP-321 payment must include an address.',
        );
      }
      if (builder.amount != null && builder.reqAsset != null) {
        throw const Zip321ParseException(
          'A ZIP-321 payment cannot include both amount and req-asset.',
        );
      }
      if (builder.memo != null && _isTransparentAddress(builder.address!)) {
        throw const Zip321ParseException(
          'Transparent ZIP-321 payments cannot include a memo.',
        );
      }
      parsedPayments.add(
        Zip321Payment(
          address: builder.address!,
          amount: builder.amount,
          label: builder.label,
          message: builder.message,
          memoBase64Url: builder.memo,
          memoText: builder.memoText,
          memoIsBinary: builder.memoIsBinary,
          reqAssetBase64Url: builder.reqAsset,
        ),
      );
    }

    final hasBinaryMemo = parsedPayments.any((payment) => payment.memoIsBinary);
    final unsupportedReason = parsedPayments.length > 1
        ? 'Multiple-recipient ZIP-321 requests are parsed but not supported yet.'
        : hasBinaryMemo
        ? 'Binary ZIP-321 memos are parsed but not supported yet.'
        : hasCustomAsset
        ? 'Custom asset ZIP-321 requests are parsed but not supported yet.'
        : null;

    return Zip321PaymentRequest(
      payments: parsedPayments,
      unsupportedReason: unsupportedReason,
    );
  }
}

const _recognizedParamNames = {
  'address',
  'amount',
  'label',
  'message',
  'memo',
  'req-asset',
};
const _maxMemoBase64UrlLength = 684; // ceil(512 / 3) * 4

class Zip321Payment {
  const Zip321Payment({
    required this.address,
    this.amount,
    this.label,
    this.message,
    this.memoBase64Url,
    this.memoText,
    this.memoIsBinary = false,
    this.reqAssetBase64Url,
  });

  final String address;
  final String? amount;
  final String? label;
  final String? message;
  final String? memoBase64Url;
  final String? memoText;
  final bool memoIsBinary;
  final String? reqAssetBase64Url;
}

class Zip321ParseException implements Exception {
  const Zip321ParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A `zcash:` link that parsed cleanly but asks for something Vizor does not
/// implement yet — see [Zip321PaymentRequest.unsupportedReason].
///
/// Separate from [Zip321ParseException] so a surface can tell "we cannot do
/// this yet" apart from "this link is broken" without matching on the spec
/// wording of a parse message. Both reasons are for the log; the user-facing
/// sentence comes from `paymentUriRejectionMessage`.
class Zip321UnsupportedRequestException implements Exception {
  const Zip321UnsupportedRequestException(this.reason);

  /// The parser's own wording, for the log. Never shown to the user.
  final String reason;

  @override
  String toString() => reason;
}

class _Zip321PaymentBuilder {
  _Zip321PaymentBuilder({required this.index});

  final String index;
  String? address;
  String? amount;
  String? label;
  String? message;
  String? memo;
  String? memoText;
  bool memoIsBinary = false;
  String? reqAsset;
}

class _Zip321ParamName {
  const _Zip321ParamName({required this.name, required this.index});

  final String name;
  final String index;
}

_Zip321ParamName _parseParamName(String rawName) {
  if (rawName.contains('%')) {
    throw const Zip321ParseException(
      'ZIP-321 parameter names must not be percent-encoded.',
    );
  }
  final match = RegExp(
    r'^([A-Za-z][A-Za-z0-9+-]*)(?:\.([1-9][0-9]{0,3}))?$',
  ).firstMatch(rawName);
  if (match == null) {
    throw const Zip321ParseException('Invalid ZIP-321 parameter name.');
  }
  return _Zip321ParamName(name: match.group(1)!, index: match.group(2) ?? '');
}

void _validateAddress(String value) {
  if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(value)) {
    throw const Zip321ParseException('Invalid ZIP-321 payment address.');
  }
}

void _validateAmount(String value) {
  if (value.contains('%')) {
    throw const Zip321ParseException(
      'ZIP-321 amount must not be percent-encoded.',
    );
  }
  if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,8})?$').hasMatch(value)) {
    throw const Zip321ParseException('Invalid ZIP-321 ZEC amount.');
  }
  final parsed = double.tryParse(value);
  if (parsed == null || parsed > 21000000) {
    throw const Zip321ParseException('ZIP-321 amount exceeds the ZEC supply.');
  }
}

void _validateBase64Url(String value, String label) {
  if (!RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(value)) {
    throw Zip321ParseException('$label must be base64url without padding.');
  }
}

({String? text, bool isBinary}) _parseMemo(String value) {
  _validateBase64Url(value, 'memo');
  if (value.length > _maxMemoBase64UrlLength) {
    throw const Zip321ParseException('ZIP-321 memo exceeds 512 bytes.');
  }
  final bytes = _decodeBase64UrlBytes(value, 'memo');
  if (bytes.length > 512) {
    throw const Zip321ParseException('ZIP-321 memo exceeds 512 bytes.');
  }
  // ZIP-302 memos are a fixed 512-byte field that producers zero-pad on the
  // right, so a full-width encoding of "Invoice 42" arrives as the text plus
  // 502 trailing NULs. Drop that padding before decoding; interior NULs stay
  // in place and are still rejected as unsupported control characters.
  final unpadded = _stripTrailingMemoPadding(bytes);
  try {
    final text = utf8.decode(unpadded, allowMalformed: false);
    if (_containsUnsupportedMemoText(text)) {
      throw const Zip321ParseException(
        'ZIP-321 memo contains unsupported control characters.',
      );
    }
    return (text: text, isBinary: false);
  } on FormatException {
    return (text: null, isBinary: true);
  }
}

List<int> _stripTrailingMemoPadding(List<int> bytes) {
  var end = bytes.length;
  while (end > 0 && bytes[end - 1] == 0x00) {
    end--;
  }
  return end == bytes.length ? bytes : bytes.sublist(0, end);
}

bool _containsUnsupportedMemoText(String value) =>
    value.runes.any(_isUnsupportedMemoCodePoint);

/// Whether [text] can travel as a ZIP-321 memo this parser will accept:
/// no bidi controls, no C0/C1 control characters other than tab, LF and CR.
///
/// Producers (the request composer) call this so every artefact the wallet
/// hands out round-trips through its own parser.
bool zip321MemoTextIsSupported(String text) =>
    !_containsUnsupportedMemoText(text);

/// [text] with every code point the parser refuses removed. The characters
/// dropped are invisible (bidi overrides, control characters), so the visible
/// message is unchanged.
String stripUnsupportedZip321MemoText(String text) {
  if (!_containsUnsupportedMemoText(text)) return text;
  return String.fromCharCodes(
    text.runes.where((codePoint) => !_isUnsupportedMemoCodePoint(codePoint)),
  );
}

bool _isUnsupportedMemoCodePoint(int codePoint) {
  if (_bidiControlCodePoints.contains(codePoint)) return true;
  if (codePoint < 0x20) {
    return codePoint != 0x09 && codePoint != 0x0A && codePoint != 0x0D;
  }
  return codePoint >= 0x7F && codePoint <= 0x9F;
}

const _bidiControlCodePoints = <int>{
  0x061C,
  0x200E,
  0x200F,
  0x202A,
  0x202B,
  0x202C,
  0x202D,
  0x202E,
  0x2066,
  0x2067,
  0x2068,
  0x2069,
};

List<int> _decodeBase64UrlBytes(String value, String label) {
  final normalized = value.padRight(
    value.length + (4 - value.length % 4) % 4,
    '=',
  );
  try {
    return base64Url.decode(normalized);
  } on FormatException {
    throw Zip321ParseException('$label is not valid base64url.');
  }
}

String _echoSafe(String value) => value.length <= _maxEchoedNameLength
    ? value
    : '${value.substring(0, _maxEchoedNameLength)}\u2026';

String _decodeQChar(String value, String label) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    throw Zip321ParseException(
      'Invalid percent encoding in ${_echoSafe(label)}.',
    );
  }
}

bool _isTransparentAddress(String address) {
  return address.startsWith('t');
}

int _indexSortValue(String index) {
  return index.isEmpty ? 0 : int.parse(index);
}
