import 'dart:convert';

class Zip321PaymentRequest {
  const Zip321PaymentRequest({required this.payments, this.unsupportedReason});

  final List<Zip321Payment> payments;
  final String? unsupportedReason;

  bool get isSupported => unsupportedReason == null;

  Zip321Payment get primaryPayment => payments.first;

  static Zip321PaymentRequest parse(String input) {
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
              'Required ZIP-321 parameter $name is not supported.',
            );
          }
          continue;
        }
        if (!seenKeys.add(seenKey)) {
          throw Zip321ParseException('Duplicate $name parameter.');
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
  final bytes = _decodeBase64UrlBytes(value, 'memo');
  if (bytes.length > 512) {
    throw const Zip321ParseException('ZIP-321 memo exceeds 512 bytes.');
  }
  try {
    return (text: utf8.decode(bytes, allowMalformed: false), isBinary: false);
  } on FormatException {
    return (text: null, isBinary: true);
  }
}

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

String _decodeQChar(String value, String label) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    throw Zip321ParseException('Invalid percent encoding in $label.');
  }
}

bool _isTransparentAddress(String address) {
  return address.startsWith('t');
}

int _indexSortValue(String index) {
  return index.isEmpty ? 0 : int.parse(index);
}
